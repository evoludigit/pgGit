//! Repository automation. `cargo xtask ci` runs the same gate as CI: format
//! check, clippy with warnings denied, then the test suite.

use std::process::{Command, ExitCode};

fn main() -> ExitCode {
    let task = std::env::args().nth(1);
    if task.as_deref() == Some("ci") {
        ci()
    } else {
        eprintln!("usage: cargo xtask ci");
        ExitCode::from(2)
    }
}

fn ci() -> ExitCode {
    let gates: &[&[&str]] = &[
        &["fmt", "--all", "--check"],
        &[
            "clippy",
            "--workspace",
            "--all-targets",
            "--all-features",
            "--",
            "-D",
            "warnings",
        ],
    ];
    for args in gates {
        if !run(args) {
            return ExitCode::FAILURE;
        }
    }
    let tests: &[&str] = if has_nextest() {
        &["nextest", "run", "--workspace", "--all-features"]
    } else {
        &["test", "--workspace", "--all-features"]
    };
    if run(tests) {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn has_nextest() -> bool {
    Command::new("cargo")
        .args(["nextest", "--version"])
        .output()
        .is_ok_and(|output| output.status.success())
}

fn run(args: &[&str]) -> bool {
    eprintln!("$ cargo {}", args.join(" "));
    Command::new("cargo").args(args).status().is_ok_and(|status| status.success())
}
