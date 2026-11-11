use std::path::Path;
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: inspect input.tendies new-absolute-output-directory");
        std::process::exit(2);
    }
    match posterbridge_core::archive::extract(Path::new(&args[1]), Path::new(&args[2])) {
        Ok(report) => println!("{}", serde_json::to_string_pretty(&report).unwrap()),
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(1);
        }
    }
}
