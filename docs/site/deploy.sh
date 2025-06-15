#!/bin/bash

# Deployment script for pgGit documentation
# Supports various static hosting platforms

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Check if site is built
if [ ! -d "site" ]; then
    echo -e "${RED}Error: Site not built. Run ./build.sh first${NC}"
    exit 1
fi

echo -e "${BLUE}pgGit Documentation Deployment${NC}"
echo "Choose deployment target:"
echo "1) GitHub Pages"
echo "2) Netlify Drop"
echo "3) Vercel"
echo "4) Local nginx"
echo "5) Generate nginx config only"

read -p "Select option (1-5): " choice

case $choice in
    1)
        echo -e "${BLUE}Deploying to GitHub Pages...${NC}"
        # Create gh-pages branch if it doesn't exist
        git checkout -B gh-pages
        # Copy site contents to root
        cp -r site/* .
        # Add and commit
        git add -A
        git commit -m "Deploy pgGit documentation"
        git push origin gh-pages --force
        git checkout main
        echo -e "${GREEN}Deployed! Visit https://[username].github.io/pggit${NC}"
        ;;
    
    2)
        echo -e "${BLUE}Creating Netlify drop...${NC}"
        cd site
        zip -r ../pggit-docs.zip .
        cd ..
        echo -e "${GREEN}Created pggit-docs.zip${NC}"
        echo "Visit https://app.netlify.com/drop to upload"
        ;;
    
    3)
        echo -e "${BLUE}Deploying to Vercel...${NC}"
        if command -v vercel &> /dev/null; then
            cd site
            vercel --prod
            cd ..
        else
            echo -e "${RED}Vercel CLI not installed. Run: npm i -g vercel${NC}"
        fi
        ;;
    
    4)
        echo -e "${BLUE}Setting up local nginx...${NC}"
        sudo cp nginx.conf /etc/nginx/sites-available/pggit
        sudo ln -sf /etc/nginx/sites-available/pggit /etc/nginx/sites-enabled/
        sudo nginx -t && sudo systemctl reload nginx
        echo -e "${GREEN}Configured! Add 'pggit.local' to /etc/hosts${NC}"
        ;;
    
    5)
        echo -e "${BLUE}Generated nginx.conf${NC}"
        ;;
    
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac