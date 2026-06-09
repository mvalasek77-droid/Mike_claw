/// Minimal standalone server binary for the CodeGenie Claw build pipeline.
/// Uses the runtime crate's server module directly.
///
/// Usage: claw-serve [port]
/// Default port: 8765

fn main() {
    let port: u16 = std::env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(8765);

    println!("claw-serve: starting on 0.0.0.0:{port}");

    let rt = tokio::runtime::Runtime::new().expect("failed to create tokio runtime");
    rt.block_on(async {
        if let Err(e) = runtime::server::serve(port).await {
            eprintln!("claw-serve error: {e}");
            std::process::exit(1);
        }
    });
}