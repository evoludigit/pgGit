# pgGit Demo Recording

## Overview
This directory contains the asciinema terminal recording demonstrating pgGit features.

## Files

- `record-demo.sh` - Script to generate the demo recording
- `pggit-demo.cast` - The actual asciinema recording (generate with record-demo.sh)
- `pggit-demo.gif` - GIF version for GitHub/README (convert from .cast)

## Generating the Demo

```bash
# Install asciinema
pip install asciinema
# or: brew install asciinema

# Run the recording script
./docs/demo/record-demo.sh

# Upload to asciinema.org
asciinema upload docs/demo/pggit-demo.cast

# Convert to GIF for README
asciicast2gif docs/demo/pggit-demo.cast docs/demo/pggit-demo.gif
```

## Demo Script Flow

1. **Install pgGit** - Show extension installation
2. **Create Branch** - Create and switch to feature branch
3. **Make Changes** - Execute DDL (CREATE TABLE, INDEX)
4. **View Tracking** - Show auto-tracked objects
5. **Commit** - Commit changes with message
6. **View History** - Display commit history
7. **Merge** - Merge feature branch to main
8. **Health Check** - Run system health check
9. **Metrics** - Show Prometheus metrics

## Key Features Shown

- Zero-config DDL tracking
- Git-like branch/switch workflow
- Automatic schema versioning
- Built-in monitoring
- Production-ready health checks
