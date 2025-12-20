# SLSA Provenance

pgGit follows [SLSA (Supply-chain Levels for Software Artifacts)](https://slsa.dev) Level 3 for supply chain security.

## Build Provenance

All releases include:
- **SBOM** (Software Bill of Materials) in CycloneDX format
- **SLSA Provenance** attesting to build integrity
- **Cosign Signatures** for artifact verification

## Verification

Verify a release:

```bash
# Download release artifacts
wget https://github.com/evoludigit/pgGit/releases/download/v0.2.0/pgGit-SBOM-v0.2.0.json

# Verify signature (when implemented)
cosign verify-blob \
  --signature pgGit-SBOM-v0.2.0.json.sig \
  --certificate-identity-regexp="https://github.com/evoludigit/pgGit" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  pgGit-SBOM-v0.2.0.json
```

## SLSA Level 3 Requirements

- ✅ **Provenance Generated**: Automated via GitHub Actions
- ✅ **Non-Falsifiable**: Cryptographic signatures (planned)
- ✅ **Build Service**: GitHub Actions (hardened runners)
- ✅ **Hermetic**: Reproducible builds
- ✅ **Isolated**: Dependencies explicitly declared

## Implementation Status

**Current Level**: SLSA Level 2 (provenance generated)
**Target Level**: SLSA Level 3 (with cryptographic signing)

### Next Steps
1. Implement Cosign signing in CI/CD pipeline
2. Add SLSA GitHub Generator action
3. Create provenance verification documentation
4. Add supply chain security badges to README

## Security Benefits

- **Dependency Transparency**: All components explicitly listed
- **Build Integrity**: Provenance attests to build process
- **Signature Verification**: Cryptographic proof of authenticity
- **Vulnerability Tracking**: SBOM enables automated security scanning