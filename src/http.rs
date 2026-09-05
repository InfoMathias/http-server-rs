use std::io::{self, Write};

pub struct Response {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl Response {
    pub fn new(status: u16) -> Self {
        Response { status, headers: Vec::new(), body: Vec::new() }
    }

    pub fn with_header(mut self, name: &str, value: &str) -> Self {
        self.headers.push((name.to_string(), value.to_string()));
        self
    }

    pub fn with_body(mut self, bytes: impl Into<Vec<u8>>) -> Self {
        self.body = bytes.into();
        self       
    }

    fn reason(&self) -> &'static str {
        match self.status {
            200 => "OK",
            201 => "Created",
            400 => "Bad Request",
            404 => "Not Found",
            405 => "Method Not Allowed",
            500 => "Internal Server Error",
            _ => "Unknown",
        }
    }

    pub fn write_to(&self, mut stream: impl Write) -> io::Result<()> {
        let mut out = Vec::new();
        write!(out, "HTTP/1.1 {} {}\r\n", self.status, self.reason())?;
        for (name, value) in &self.headers {
            write!(out, "{}: {}\r\n", name, value)?;
        }
        write!(out, "Content-Length: {}\r\n\r\n", self.body.len())?;
        out.extend_from_slice(&self.body);
        stream.write_all(&out)
    }
}