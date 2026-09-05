#[allow(unused_imports)]
 
use std::{
    net::{TcpListener, TcpStream},
    sync::Arc,
    thread,
};

mod routes;
mod http;
mod router;
use crate::router::Router;

fn main() {
    
    
    let args: Vec<String> = std::env::args().collect();
    let mut directory = String::new();

    let mut i = 0;
    while i < args.len() {
        if args[i] == "--directory" {
            if i + 1 < args.len() {
                directory = args[i + 1].clone();
            }
        }
        i += 1;
    }

    println!("{}", directory);

    let mut router = Router::new();
    routes::build_routes(&mut router);

    let router = Arc::new(router);
    let directory = Arc::new(directory);

    let listener = TcpListener::bind("127.0.0.1:4221").unwrap();

    for stream in listener.incoming() {
        let router = Arc::clone(&router);
        let directory = Arc::clone(&directory);

        thread::spawn(move || {
            match stream {
                Ok(stream) => {
                    println!("accepted new connection");

                    loop {
                        let keep_alive = router.respond(&stream, &directory);
                        if !keep_alive {
                            break;
                        }
                    }
                }
                Err(e) => {
                    println!("error: {}", e);
                }
            }
        });
    }
}

