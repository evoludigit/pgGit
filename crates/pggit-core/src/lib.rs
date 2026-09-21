//! pgGit core: schema snapshots, the metadata repository, and branch and commit
//! operations.
//!
//! This crate is a library first so that fraisier-core can embed it as a
//! rehearsal-database backend. The command-line interface in `crates/pggit` is
//! a thin layer over it.

/// Version of the JSON output contract that every command emits.
pub const CONTRACT_VERSION: &str = "v1";

#[cfg(test)]
mod tests {
    use super::CONTRACT_VERSION;

    #[test]
    fn contract_version_is_v1() {
        assert_eq!(CONTRACT_VERSION, "v1");
    }
}
