use std::{
    net::{TcpStream},
    io::{BufReader, prelude::*},
    collections::{HashMap},
};

use crate::http::Response;

type Handler = Box<dyn Fn(&HashMap<String, String>) -> Response + Send + Sync>;

pub struct Router {
    routes: HashMap<String, HashMap<String, Handler>>,
}

impl Router {    

    pub fn new() -> Self {
        Router {
            routes: HashMap::new(),
        }
    }

    pub fn add_route(&mut self, path: &str, method: &str, handler: Handler) {
            self.routes
                .entry(path.to_string())
                .or_insert_with(HashMap::new)
                .insert(method.to_string(), Box::new(handler));
    }

    pub fn respond(&self, stream: &TcpStream, directory: &str) -> bool {

        let (method, path, headers, body) = Self::parse_routing_args(&stream);
        let mut response = self.handle(&path, &method, &headers, &directory, &body);
        if let Some(encoding) = Self::negociate_encoding(&headers) {
            response = response.with_header("Content-Encoding", &encoding);
        }

        
        let keep_alive = match headers.get("connection") {
            Some(val) if val.eq_ignore_ascii_case("close") => false,
            _ => true,
        };

        let response = response.with_header(
            "Connection",
            if keep_alive { "keep-alive" } else { "close" },
        );

        response.write_to(stream).is_ok() && keep_alive
    }

    pub fn handle(
        &self, 
        path: &str, 
        method: &str,
        headers: &HashMap<String, String>,
        directory: &str,
        body: &str,
    ) -> Response {

        for (route_path, methods_map) in &self.routes {
            if let Some(mut params) = Self::match_path(route_path, path) {

                for (k, v) in headers {
                    params.insert(k.clone(), v.clone());
                }

                if !directory.trim().is_empty() {
                    params.insert("directory".to_string(), directory.to_string());
                }

                if !body.trim().is_empty() {
                    params.insert("body".to_string(), body.to_string());
                }

                if let Some(handler) = methods_map.get(method) {
                    return handler(&params);
                } else {
                    let allowed: Vec<String> = methods_map.keys().cloned().collect();
                    return Response::new(405).with_header("Allow", &allowed.join(", "));
                }
            }
        }

        Response::new(404)
    }

    fn match_path(route: &str, actual: &str) -> Option<HashMap<String, String>> {
        let route_parts: Vec<&str> = route.trim_matches('/').split('/').collect();
        let actual_parts: Vec<&str> = actual.trim_matches('/').split('/').collect();

        if route_parts.len() != actual_parts.len() {
            return None;
        }

        let mut params = HashMap::new();

        for (r, a) in route_parts.iter().zip(actual_parts.iter()) {
            if r.starts_with(':') {
                params.insert(r[1..].to_string(), a.to_string());
            } else if r != a {
                return None;
            }
        }

        println!("{:?}", params);

        Some(params)
    }

    

    fn parse_routing_args(stream: &TcpStream) -> (String, String, HashMap<String, String>, String) {
        let mut buf_reader = BufReader::new(stream);
        let mut http_request = Vec::new();
        let mut line = String::new();

        loop {
            line.clear();
            let bytes_read = buf_reader.read_line(&mut line).unwrap_or(0);
            if bytes_read == 0 || line.trim().is_empty() {
                break;
            }
            http_request.push(line.trim_end().to_string());
        }

        if http_request.is_empty() {
            return (String::new(), String::new(), HashMap::new(), String::new());
        }

        let mut parts = http_request[0].split_whitespace();
        let method = parts.next().unwrap_or_default().to_string();
        let path = parts.next().unwrap_or_default().to_string();

        let mut headers_map = HashMap::new();
        for line in http_request.iter().skip(1) {
            if let Some((key, value)) = line.split_once(':') {
                headers_map.insert(key.trim().to_lowercase(), value.trim().to_string());
            }
        }

        let body = if let Some(content_length) = headers_map.get("content-length") {
            if let Ok(len) = content_length.parse::<usize>() {
                let mut body_buf = vec![0; len];
                buf_reader.read_exact(&mut body_buf).unwrap_or(());
                String::from_utf8_lossy(&body_buf).to_string()
            } else {
                String::new()
            }
        } else {
            String::new()
        };

        (method, path, headers_map, body)
    }

    fn negociate_encoding(headers: &HashMap<String, String>) -> Option<String> {
        let accepted = headers.get("accept-encoding")?;

        let encoding = accepted
            .split(',')
            .map(str::trim)
            .find(|x| *x == "gzip")
            .map(str::to_owned);

        encoding
    }
}
