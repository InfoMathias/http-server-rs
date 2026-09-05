[![progress-banner](https://backend.codecrafters.io/progress/http-server/0de2b18f-1200-4ef0-baec-ada3b54dc648)](https://app.codecrafters.io/users/codecrafters-bot?r=2qF)

# Rust HTTP Server

This repository contains my own HTTP/1.1 server written in Rust, created as part of the [**Build Your Own HTTP Server**](https://app.codecrafters.io/courses/http-server/overview) challenge on CodeCrafters.  

The goal was to start from a bare TCP socket and gradually build a fully functional HTTP Server.

## Features Implemented

- **Basic HTTP Response** – Sends valid `HTTP/1.1 200 OK` responses.
- **Path Extraction** – Reads and interprets URL paths from requests.
- **Header Parsing** – Reads HTTP headers for request handling.
- **Concurrent Connections** – Handles multiple clients at once using threads.
- **Static File Serving** – Returns files from disk with correct headers.
- **Request Body Parsing** – Reads POST/PUT bodies for dynamic handling.
- **HTTP Compression** – Negotiates `Accept-Encoding` and gzip-compresses response bodies.
- **Persistent Connections** – Keeps TCP connections open for multiple requests.
- **Graceful Connection Closure** – Cleans up resources properly after use.

---

## Available Routes

| Method | Path | Description |
|--------|------|-------------|
| **GET** | `/` | Returns `200 OK` with no body. |
| **GET** | `/echo/:str` | Echoes back `:str` in the response body with `Content-Type: text/plain`. |
| **GET** | `/user-agent` | Returns the `User-Agent` header value in plain text. |
| **GET** | `/files/:filename` | Returns the contents of `:filename` from the given `--directory` path. |
| **POST** | `/files/:filename` | Creates or overwrites `:filename` in the given `--directory` with the request body. |

> **Note:** For file routes (`/files/...`), you **must** provide a directory at launch:
>
> ```sh
> ./your_program.sh --directory /path/to/files
> ```
> The `--directory` flag tells the server where to read and write files.

---

## Example Usage

### 1. Echo back text
curl http://localhost:4221/echo/hello

### 2. Read the User-Agent header
curl http://localhost:4221/user-agent -H "User-Agent: my-client"

### 3. Serve a file (must exist in the --directory path)
curl http://localhost:4221/files/test.txt

### 4. Upload a file
curl -X POST http://localhost:4221/files/new.txt \
     --data 'This is file content'

### 5. Request a gzip-compressed response
curl http://localhost:4221/echo/hello -H "Accept-Encoding: gzip" --compressed

---

## How to Run

You’ll need **Rust** (`cargo 1.87+`) installed.

```sh
# Build & run
./your_program.sh
