#!/bin/bash
# pggit.dev deployment script
# Simple deployment for solo dev setup

set -e

# Configuration - UPDATE THESE VALUES
SERVER_USER="your-username"
SERVER_HOST="your-server.com"
SERVER_PATH="/var/www/pggit.dev"
DOCS_DIR="docs-web"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 Deploying pggit.dev documentation...${NC}"

# Check if docs directory exists
if [ ! -d "$DOCS_DIR" ]; then
    echo -e "${RED}❌ Error: $DOCS_DIR directory not found${NC}"
    echo "Run this script from the pggit project root"
    exit 1
fi

# Validate required files
echo -e "${YELLOW}📋 Validating files...${NC}"
required_files=("$DOCS_DIR/index.html" "$DOCS_DIR/style.css")
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}❌ Missing required file: $file${NC}"
        exit 1
    fi
done

# Show what will be deployed
echo -e "${YELLOW}📦 Files to deploy:${NC}"
find "$DOCS_DIR" -type f | head -10
total_files=$(find "$DOCS_DIR" -type f | wc -l)
echo "... and $((total_files - 10)) more files"

# Confirm deployment
echo -e "${YELLOW}🎯 Target: $SERVER_USER@$SERVER_HOST:$SERVER_PATH${NC}"
read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}⏸️  Deployment cancelled${NC}"
    exit 0
fi

# Deploy using rsync
echo -e "${YELLOW}🚀 Deploying to server...${NC}"
rsync -avz --delete \
    --exclude='.DS_Store' \
    --exclude='Thumbs.db' \
    --exclude='.git*' \
    "$DOCS_DIR/" \
    "$SERVER_USER@$SERVER_HOST:$SERVER_PATH/"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment successful!${NC}"
    echo -e "${GREEN}🌐 Your site should be live at: https://pggit.dev${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Test the site in your browser"
    echo "2. Check nginx logs if needed: sudo tail -f /var/log/nginx/access.log"
    echo "3. Update DNS if this is first deployment"
else
    echo -e "${RED}❌ Deployment failed${NC}"
    echo "Check your SSH connection and server path"
    exit 1
fi