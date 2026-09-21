//! Schema engine boundary.
//!
//! DDL-level diff and apply are delegated to an external tool. This crate
//! names the engines pgGit can drive; the trait and its adapters follow.

use std::fmt;

/// Engines pgGit knows how to drive.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EngineKind {
    /// confiture, the FraiseQL stack's migration tool. Chosen by default when
    /// `db/environments/` exists in the project.
    Confiture,
    /// pgschema, for projects outside the FraiseQL stack.
    Pgschema,
}

impl fmt::Display for EngineKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Confiture => "confiture",
            Self::Pgschema => "pgschema",
        })
    }
}

#[cfg(test)]
mod tests {
    use super::EngineKind;

    #[test]
    fn engine_names_match_their_binaries() {
        assert_eq!(EngineKind::Confiture.to_string(), "confiture");
        assert_eq!(EngineKind::Pgschema.to_string(), "pgschema");
    }
}
