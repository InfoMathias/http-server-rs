#!/usr/bin/env bash
# Checklist smoke runner for the http-server refactor.
#
#   ./smoke.sh              build, start server, run checks, print board, stop
#   ./smoke.sh --watch      same, re-running on every save to src/ or Cargo.toml
#   ./smoke.sh --attach     skip build/start, test a server you're already running
#   ./smoke.sh --port 4221  override the port
#
# Exit status is the number of failing checks, so it slots into a pre-commit hook.

set -u

PORT=4221
WATCH=0
ATTACH=0
TIMEOUT=2

while [ $# -gt 0 ]; do
  case "$1" in
    --watch)  WATCH=1 ;;
    --attach) ATTACH=1 ;;
    --port)   PORT="$2"; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

BASE="http://localhost:$PORT"
BIN=./target/debug/codecrafters-http-server.exe
[ -f "$BIN" ] || BIN=./target/debug/codecrafters-http-server

if [ -t 1 ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; B=$'\033[1m'; N=$'\033[0m'
else
  G=; R=; Y=; D=; B=; N=
fi

TMP=$(mktemp -d)
DIR="$TMP/files"
LOG="$TMP/server.log"
SRV_PID=""

# ---------------------------------------------------------------- server ----

stop_server() {
  [ -n "$SRV_PID" ] || return 0
  kill "$SRV_PID" 2>/dev/null || taskkill //F //PID "$SRV_PID" >/dev/null 2>&1
  wait "$SRV_PID" 2>/dev/null
  SRV_PID=""
}

cleanup() { stop_server; rm -rf "$TMP"; }
trap cleanup EXIT

# connection refused is curl exit 7; anything else means something is listening
port_busy() {
  curl -s -m 1 -o /dev/null "$BASE/echo/ping" 2>/dev/null
  [ $? -ne 7 ]
}

start_server() {
  mkdir -p "$DIR"
  printf 'hello file' > "$DIR/foo.txt"
  head -c 256 /dev/urandom > "$DIR/bin.dat"

  [ "$ATTACH" = 1 ] && return 0

  if port_busy; then
    taskkill //F //IM codecrafters-http-server.exe >/dev/null 2>&1
    sleep 0.3
  fi

  "$BIN" --directory "$DIR/" > "$LOG" 2>&1 &
  SRV_PID=$!

  local i=0
  while [ $i -lt 50 ]; do
    port_busy && return 0
    kill -0 "$SRV_PID" 2>/dev/null || return 1
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

# ----------------------------------------------------------------- checks ----

names=(); marks=(); notes=(); groups=(); group=""

sect() { group="$1"; }
ok()   { groups+=("$group"); names+=("$1"); marks+=(1); notes+=(""); }
no()   { groups+=("$group"); names+=("$1"); marks+=(0); notes+=("$2"); }
skip() { groups+=("$group"); names+=("$1"); marks+=(2); notes+=("$2"); }

# req <curl args...> -> RC, CODE, $TMP/h (headers), $TMP/b (body)
req() {
  CODE=$(curl -s -m "$TIMEOUT" -D "$TMP/h" -o "$TMP/b" -w '%{http_code}' "$@" 2>/dev/null)
  RC=$?
}

hdr() { grep -i "^$1:" "$TMP/h" 2>/dev/null | head -1 | cut -d: -f2- | tr -d ' \r'; }

# expect <name> <want-status> <curl args...>
expect() {
  local name="$1" want="$2"
  shift 2
  req "$@"
  if [ "$RC" -ne 0 ]; then
    no "$name" "no complete response in ${TIMEOUT}s (curl $RC) - missing Content-Length?"
  elif [ "$CODE" != "$want" ]; then
    no "$name" "want $want, got $CODE"
  else
    ok "$name"
  fi
}

# expect_body <name> <want-status> <want-body> <curl args...>
expect_body() {
  local name="$1" want="$2" wantbody="$3"
  shift 3
  req "$@"
  local got
  got=$(cat "$TMP/b")
  if [ "$RC" -ne 0 ]; then
    no "$name" "no complete response in ${TIMEOUT}s (curl $RC)"
  elif [ "$CODE" != "$want" ]; then
    no "$name" "want $want, got $CODE"
  elif [ "$got" != "$wantbody" ]; then
    no "$name" "body [$got] != [$wantbody]"
  else
    ok "$name"
  fi
}

run_checks() {
  names=(); marks=(); notes=(); groups=()
  local got cl al n

  sect "routes"
  expect      "GET / -> 200"                 200 "$BASE/"
  expect_body "GET /echo/abc"                200 "abc" "$BASE/echo/abc"
  expect_body "GET /user-agent"              200 "bar/1.0" -H 'User-Agent: bar/1.0' "$BASE/user-agent"
  expect      "GET /nonsense -> 404"         404 "$BASE/nonsense"
  expect      "PUT /files/foo.txt -> 405"    405 -X PUT "$BASE/files/foo.txt"

  sect "files"
  expect_body "GET /files/foo.txt"           200 "hello file" "$BASE/files/foo.txt"
  expect      "GET /files/nope -> 404"       404 "$BASE/files/nope"
  expect      "POST /files/new.txt -> 201"   201 -X POST --data 'created body' "$BASE/files/new.txt"

  if [ -f "$DIR/new.txt" ]; then
    got=$(cat "$DIR/new.txt")
    if [ "$got" = "created body" ]; then
      ok "POST wrote correct bytes"
    else
      no "POST wrote correct bytes" "on disk: [$got]"
    fi
  else
    no "POST wrote correct bytes" "new.txt was never created"
  fi

  if timeout "$TIMEOUT" curl -s "$BASE/files/bin.dat" 2>/dev/null | cmp -s - "$DIR/bin.dat"; then
    ok "binary file byte-identical"
  else
    no "binary file byte-identical" "read_to_string mangles non-UTF-8 + miscounts length"
  fi

  sect "framing"
  req "$BASE/"
  if [ "$RC" -ne 0 ]; then
    no "GET / is self-delimiting" "client cannot tell where the body ends"
  elif [ -n "$(hdr content-length)" ] || [ "$(hdr transfer-encoding)" = "chunked" ]; then
    ok "GET / is self-delimiting"
  else
    no "GET / is self-delimiting" "no Content-Length and no chunked encoding"
  fi

  req "$BASE/echo/abcde"
  cl=$(hdr content-length)
  if [ "$cl" = "5" ]; then
    ok "echo Content-Length correct"
  else
    no "echo Content-Length correct" "header says [${cl:-absent}], body is 5 bytes"
  fi

  req "$BASE/no-such-route"
  cl=$(hdr content-length)
  if [ "$RC" -eq 0 ] && [ -n "$cl" ]; then
    ok "404 carries Content-Length"
  else
    no "404 carries Content-Length" "header is [${cl:-absent}]"
  fi

  req -X PUT "$BASE/files/foo.txt"
  al=$(hdr allow)
  if [ "$RC" -eq 0 ] && [ -n "$al" ]; then
    ok "405 sends Allow header"
  else
    no "405 sends Allow header" "header is [${al:-absent}] (currently baked into the body)"
  fi

  sect "connections"
  got=$(timeout "$TIMEOUT" curl -s "$BASE/echo/a" "$BASE/echo/b" 2>/dev/null | tr -d '\r\n')
  if [ "$got" = "ab" ]; then
    ok "keep-alive: 2 reqs, 1 socket"
  else
    no "keep-alive: 2 reqs, 1 socket" "got [$got], want [ab]"
  fi

  expect "Connection: close honored" 200 -H 'Connection: close' "$BASE/"

  # open a socket, say nothing, drop it: the EOF path
  (exec 3<>"/dev/tcp/localhost/$PORT") 2>/dev/null
  sleep 0.2
  expect "survives abrupt disconnect" 200 "$BASE/echo/still-alive"

  if [ "$ATTACH" = 1 ]; then
    skip "no panics in server log" "--attach: log not captured"
  elif grep -q 'panicked' "$LOG" 2>/dev/null; then
    n=$(grep -c 'panicked' "$LOG")
    no "no panics in server log" "$n panic(s): $(grep -m1 -A1 'panicked' "$LOG" | tail -1 | cut -c1-58)"
  else
    ok "no panics in server log"
  fi
}

# ------------------------------------------------------------------ board ----

board() {
  local build_status="$1"
  local pass=0 fail=0 skipped=0 last="" i

  printf '%shttp-server smoke%s %s%s - port %s - %s%s\n\n' \
    "$B" "$N" "$D" "$(date +%H:%M:%S)" "$PORT" "$build_status" "$N"

  for i in "${!names[@]}"; do
    if [ "${groups[$i]}" != "$last" ]; then
      last="${groups[$i]}"
      printf '  %s%s%s\n' "$D" "$last" "$N"
    fi
    case "${marks[$i]}" in
      1) printf '    %s+%s %s\n' "$G" "$N" "${names[$i]}"; pass=$((pass + 1)) ;;
      2) printf '    %s-%s %-32s %s%s%s\n' "$Y" "$N" "${names[$i]}" "$D" "${notes[$i]}" "$N"; skipped=$((skipped + 1)) ;;
      *) printf '    %sx%s %-32s %s%s%s\n' "$R" "$N" "${names[$i]}" "$D" "${notes[$i]}" "$N"; fail=$((fail + 1)) ;;
    esac
  done

  echo
  if [ "$fail" -eq 0 ]; then
    printf '  %s%d passing%s' "$G" "$pass" "$N"
  else
    printf '  %s%d passing%s - %s%d failing%s' "$G" "$pass" "$N" "$R" "$fail" "$N"
  fi
  [ "$skipped" -gt 0 ] && printf ' - %s%d skipped%s' "$Y" "$skipped" "$N"
  printf '\n\n'
  return "$fail"
}

cycle() {
  local build_status="attached" out
  if [ "$ATTACH" = 0 ]; then
    if out=$(cargo build 2>&1); then
      build_status="build ok"
    else
      printf '%shttp-server smoke%s %s%s%s - %sbuild failed%s\n\n' \
        "$B" "$N" "$D" "$(date +%H:%M:%S)" "$N" "$R" "$N"
      echo "$out" | grep -E '^error' | head -12
      echo
      return 99
    fi
    stop_server
    if ! start_server; then
      printf '  %sserver failed to start%s\n' "$R" "$N"
      sed -n '1,10p' "$LOG"
      return 98
    fi
  fi
  run_checks
  stop_server
  board "$build_status"
}

fingerprint() { ls -l src/*.rs Cargo.toml 2>/dev/null | awk '{print $6, $7, $8, $9}' | md5sum; }

if [ "$WATCH" = 1 ]; then
  last=""
  while true; do
    now=$(fingerprint)
    if [ "$now" != "$last" ]; then
      last="$now"
      clear
      cycle
      printf '  %swatching src/ for changes - ctrl-c to stop%s\n' "$D" "$N"
    fi
    sleep 1
  done
else
  cycle
  exit $?
fi
