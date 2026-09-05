use std::collections::HashMap;
use std::fs::{self, File};
use std::io::Write;
use std::path::Path;

use crate::Router;
use crate::http::Response;

pub fn build_routes(router: &mut Router) {
    router.add_route(
        "/", 
        "GET",
        Box::new(|_params: &HashMap<String, String>| Response::new(200))
    );

    router.add_route(
        "/echo/:str",
        "GET", 
        Box::new(|params: &HashMap<String, String>| {
            let binding = "".to_string();
            let path = params.get("str").unwrap_or(&binding);
            echo(path)
        })
    );

    router.add_route(
        "/user-agent",
        "GET",
        Box::new(|params: &HashMap<String, String>| {
            let binding = "".to_string();
            let agent = params.get("user-agent").unwrap_or(&binding);
            format_user_agent(agent)
        })
    );

    router.add_route(
        "files/:filename",
        "GET",
        Box::new(|params: &HashMap<String, String>| {
            let binding = "".to_string();
            let file_name = params.get("filename").unwrap_or(&binding);
            let directory = params.get("directory").unwrap_or(&binding);
            send_file_content(file_name, directory)
        })
    );

    router.add_route(
        "files/:filename",
        "POST",
        Box::new(|params: &HashMap<String, String>| {
            let binding = "".to_string();
            let file_name = params.get("filename").unwrap_or(&binding);
            let directory = params.get("directory").unwrap_or(&binding);
            let file_content = params.get("body").unwrap_or(&binding);
            create_file(file_name, directory, file_content)
        })
    );
}

fn echo(val: &str) -> Response {
    Response::new(200)
        .with_header("Content-Type", "text/plain")
        .with_body(val)
}

fn format_user_agent(agent: &str) -> Response {
    Response::new(200)
        .with_header("Content-Type", "text/plain")
        .with_body(agent)
}

fn send_file_content(file_name: &str, directory: &str) -> Response {
    let path_str = format!("{}{}", directory, file_name);
    let path = Path::new(&path_str);
    
    if !path.exists() {
        return Response::new(404);
    }

    let file_content = match fs::read(path) {
        Ok(content) => content,
        Err(_) => return Response::new(500),
    };

    Response::new(200)
        .with_header("Content-Type", "application/octet-stream")
        .with_body(file_content)
}

fn create_file(file_name: &str, directory: &str, file_content: &str) -> Response {
    if let Err(e) = fs::create_dir_all(directory) {
        return Response::new(500).with_body(format!("Failed to create directory: {}", e));
    }

    let file_path = Path::new(directory).join(file_name);

    let mut file = match File::create(file_path) {
        Ok(f) => f,
        Err(e) => return Response::new(500).with_body( format!("Failed to create file: {}", e)),
    };

    if let Err(e) = file.write_all(file_content.as_bytes()) {
        return Response::new(500).with_body(format!("Failed to write to file: {}", e));
    }
    
        Response::new(201)
}


