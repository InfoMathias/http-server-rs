#!/usr/bin/env bash
# usage: cargo run -- --directory /tmp/httpfiles/   (in another terminal)
#        ./smoke.sh
BASE=http://localhost:4221
DIR=/tmp/httpfiles
mkdir -p $DIR && printf 'hello file' > $DIR/foo.txt
head -c 256 /dev/urandom > $DIR/bin.dat

check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: expected [$2] got [$3]"; fi
}

check "root 200"     "200" "$(curl -s -o /dev/null -w '%{http_code}' $BASE/)"
check "echo body"    "abc" "$(curl -s $BASE/echo/abc)"
check "user-agent"   "bar/1.0" "$(curl -s -H 'User-Agent: bar/1.0' $BASE/user-agent)"
check "file read"    "hello file" "$(curl -s $BASE/files/foo.txt)"
check "missing 404"  "404" "$(curl -s -o /dev/null -w '%{http_code}' $BASE/files/nope)"
check "post 201"     "201" "$(curl -s -o /dev/null -w '%{http_code}' -X POST --data 'abc' $BASE/files/new.txt)"
check "unknown 404"  "404" "$(curl -s -o /dev/null -w '%{http_code}' $BASE/nonsense)"
check "keep-alive"   "ab"  "$(curl -s $BASE/echo/a $BASE/echo/b | tr -d '\n')"
check "conn close"   "200" "$(curl -s -o /dev/null -w '%{http_code}' -H 'Connection: close' $BASE/)"
check "binary file"  "same" "$(curl -s $BASE/files/bin.dat | cmp -s - $DIR/bin.dat && echo same || echo differs)"
check "wrong method" "405" "$(curl -s -o /dev/null -w '%{http_code}' -X PUT $BASE/files/foo.txt)"