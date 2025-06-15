#!/bin/bash

# Simple static site builder for pgGit documentation
# Converts Markdown to HTML with minimal dependencies

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building pgGit documentation site...${NC}"

# Create output directories
mkdir -p site/docs/getting-started/explained-like-5
mkdir -p site/docs/getting-started/explained-like-10
mkdir -p site/docs/getting-started/quickstart
mkdir -p site/docs/getting-started/troubleshooting
mkdir -p site/docs/guides/performance
mkdir -p site/docs/guides/security
mkdir -p site/docs/guides/operations
mkdir -p site/docs/architecture/overview
mkdir -p site/docs/architecture/branching
mkdir -p site/docs/architecture/ai-integration
mkdir -p site/docs/advanced/enterprise
mkdir -p site/docs/advanced/local-llm
mkdir -p site/docs/advanced/patterns
mkdir -p site/docs/contributing/guide
mkdir -p site/docs/contributing/claude
mkdir -p site/api
mkdir -p site/examples

# Function to convert markdown to HTML with pandoc or fallback
convert_md() {
    local input=$1
    local output=$2
    local title=$3
    
    if command -v pandoc &> /dev/null; then
        pandoc "$input" \
            --standalone \
            --template=template.html \
            --metadata title="$title - pgGit" \
            --toc \
            -o "$output"
    else
        # Simple fallback - just wrap in HTML
        cat > "$output" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$title - pgGit</title>
    <link rel="stylesheet" href="/style.css">
</head>
<body>
    <header>
        <nav>
            <a href="/" class="logo">pgGit</a>
            <ul>
                <li><a href="/#quick-start">Quick Start</a></li>
                <li><a href="/docs/">Documentation</a></li>
                <li><a href="/api/">API Reference</a></li>
                <li><a href="https://github.com/evoludigit/pggit">GitHub</a></li>
            </ul>
        </nav>
    </header>
    <main class="doc-content">
        <div class="markdown-body">
EOF
        # Basic markdown to HTML conversion
        sed -e 's/^# \(.*\)/<h1>\1<\/h1>/' \
            -e 's/^## \(.*\)/<h2>\1<\/h2>/' \
            -e 's/^### \(.*\)/<h3>\1<\/h3>/' \
            -e 's/```\([^`]*\)```/<pre><code>\1<\/code><\/pre>/g' \
            -e 's/`\([^`]*\)`/<code>\1<\/code>/g' \
            -e 's/^\* \(.*\)/<li>\1<\/li>/' \
            -e 's/^[0-9]\+\. \(.*\)/<li>\1<\/li>/' \
            "$input" >> "$output"
        cat >> "$output" <<EOF
        </div>
    </main>
    <footer>
        <p>pgGit is open source software under the MIT License</p>
        <p>Built with ❤️ by <a href="https://github.com/evoludigit">@evoludigit</a></p>
    </footer>
</body>
</html>
EOF
    fi
}

# Convert markdown files
echo -e "${GREEN}Converting markdown files...${NC}"

# Getting Started
convert_md "../getting-started/PgGit_Explained_Like_Im_5.md" \
    "site/docs/getting-started/explained-like-5/index.html" \
    "pgGit Explained Like You're 5"

convert_md "../getting-started/PgGit_Explained_Like_Im_10.md" \
    "site/docs/getting-started/explained-like-10/index.html" \
    "pgGit Explained Like You're 10"

convert_md "../getting-started/Getting_Started.md" \
    "site/docs/getting-started/quickstart/index.html" \
    "Quick Start Guide"

convert_md "../getting-started/Troubleshooting.md" \
    "site/docs/getting-started/troubleshooting/index.html" \
    "Troubleshooting"

# Guides
convert_md "../guides/Performance.md" \
    "site/docs/guides/performance/index.html" \
    "Performance Guide"

convert_md "../guides/Security.md" \
    "site/docs/guides/security/index.html" \
    "Security Guide"

convert_md "../guides/Operations.md" \
    "site/docs/guides/operations/index.html" \
    "Operations Guide"

# Architecture
convert_md "../Architecture_Decision.md" \
    "site/docs/architecture/overview/index.html" \
    "Architecture Overview"

convert_md "../Git_Branching_Architecture.md" \
    "site/docs/architecture/branching/index.html" \
    "Git Branching Architecture"

convert_md "../AI_Integration_Architecture.md" \
    "site/docs/architecture/ai-integration/index.html" \
    "AI Integration Architecture"

# Advanced
convert_md "../Enterprise_Features.md" \
    "site/docs/advanced/enterprise/index.html" \
    "Enterprise Features"

convert_md "../Local_LLM_Quickstart.md" \
    "site/docs/advanced/local-llm/index.html" \
    "Local LLM Quickstart"

convert_md "../Pattern_Examples.md" \
    "site/docs/advanced/patterns/index.html" \
    "Pattern Examples"

# Contributing
convert_md "../contributing/README.md" \
    "site/docs/contributing/guide/index.html" \
    "Contributing Guide"

convert_md "../contributing/Claude.md" \
    "site/docs/contributing/claude/index.html" \
    "Claude Integration"

# API Reference
convert_md "../API_Reference.md" \
    "site/api/index.html" \
    "API Reference"

# Copy static assets
echo -e "${GREEN}Copying static assets...${NC}"
cp style.css site/
cp index.html site/
cp -r docs/* site/docs/ 2>/dev/null || true

# Create a simple 404 page
cat > site/404.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 - Page Not Found</title>
    <link rel="stylesheet" href="/style.css">
</head>
<body>
    <header>
        <nav>
            <a href="/" class="logo">pgGit</a>
            <ul>
                <li><a href="/#quick-start">Quick Start</a></li>
                <li><a href="/docs/">Documentation</a></li>
                <li><a href="/api/">API Reference</a></li>
                <li><a href="https://github.com/evoludigit/pggit">GitHub</a></li>
            </ul>
        </nav>
    </header>
    <main style="text-align: center; padding: 4rem 2rem;">
        <h1>404</h1>
        <p>Page not found</p>
        <a href="/" class="button primary">Go Home</a>
    </main>
</body>
</html>
EOF

# Create robots.txt
cat > site/robots.txt <<EOF
User-agent: *
Allow: /
Sitemap: https://pggit.dev/sitemap.xml
EOF

echo -e "${BLUE}Build complete! Site generated in site/${NC}"
echo -e "${GREEN}To preview: cd site && python3 -m http.server 8000${NC}"