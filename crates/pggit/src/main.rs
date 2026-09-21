//! `pggit` command-line interface.

use clap::Parser;

/// Isolation, verification and attribution for PostgreSQL schemas.
#[derive(Debug, Parser)]
#[command(name = "pggit", version, about, long_about = None)]
struct Cli {
    /// Emit machine-readable JSON instead of tables.
    #[arg(long, global = true)]
    json: bool,
}

fn main() {
    let cli = Cli::parse();
    let version = env!("CARGO_PKG_VERSION");
    if cli.json {
        println!(
            "{{\"contract\":\"{}\",\"version\":\"{version}\"}}",
            pggit_core::CONTRACT_VERSION
        );
    } else {
        println!("pggit {version} (contract {})", pggit_core::CONTRACT_VERSION);
    }
}

#[cfg(test)]
mod tests {
    use clap::CommandFactory;

    use super::Cli;

    #[test]
    fn cli_definition_is_valid() {
        Cli::command().debug_assert();
    }
}
