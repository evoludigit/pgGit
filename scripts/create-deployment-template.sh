#!/bin/bash
# Create reusable deployment template for solo dev projects
# This will be your standard deployment pattern

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🎯 Creating Solo Dev Deployment Template...${NC}"

# Create deployment template directory
TEMPLATE_DIR="$HOME/.solo-dev-templates"
mkdir -p "$TEMPLATE_DIR"

echo -e "${YELLOW}📁 Creating template structure...${NC}"

# Create the universal deployment template
cat > "$TEMPLATE_DIR/deploy-template.sh" << 'EOF'
#!/bin/bash
# Universal deployment script for solo dev projects
# Usage: ./deploy.sh [project-name]

set -e

# Load project config
if [ -f ".deploy-config" ]; then
    source .deploy-config
else
    echo "❌ No .deploy-config found. Run ./setup-project.sh first"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_NAME=${1:-$DEFAULT_PROJECT_NAME}
DOCS_DIR=${DOCS_DIR:-"docs-web"}

echo -e "${BLUE}🚀 Deploying $PROJECT_NAME...${NC}"

# Validation
if [ ! -d "$DOCS_DIR" ]; then
    echo -e "${RED}❌ $DOCS_DIR not found${NC}"
    exit 1
fi

# Deploy
echo -e "${YELLOW}📦 Syncing files...${NC}"
rsync -avz --delete \
    --exclude='.DS_Store' \
    --exclude='Thumbs.db' \
    --exclude='.git*' \
    --exclude='node_modules' \
    "$DOCS_DIR/" \
    "$SERVER_USER@$SERVER_HOST:$SERVER_PATH/$PROJECT_NAME/"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ $PROJECT_NAME deployed successfully!${NC}"
    echo -e "${GREEN}🌐 Live at: https://$PROJECT_NAME.dev${NC}"
else
    echo -e "${RED}❌ Deployment failed${NC}"
    exit 1
fi
EOF

chmod +x "$TEMPLATE_DIR/deploy-template.sh"

# Create project setup script
cat > "$TEMPLATE_DIR/setup-project.sh" << 'EOF'
#!/bin/bash
# Setup deployment for a new solo dev project

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🎯 Setting up new solo dev project deployment...${NC}"

# Get project details
read -p "Project name (e.g., pggit): " PROJECT_NAME
read -p "Domain (e.g., pggit.dev): " DOMAIN
read -p "Docs directory (default: docs-web): " DOCS_DIR
DOCS_DIR=${DOCS_DIR:-docs-web}

# Server details (reuse across projects)
if [ ! -f "$HOME/.solo-dev-server" ]; then
    echo -e "${YELLOW}🔧 First time setup - configure your server...${NC}"
    read -p "Server username: " SERVER_USER
    read -p "Server hostname/IP: " SERVER_HOST
    read -p "Base server path (e.g., /var/www): " BASE_PATH
    
    # Save server config
    cat > "$HOME/.solo-dev-server" << EOL
SERVER_USER="$SERVER_USER"
SERVER_HOST="$SERVER_HOST"
BASE_PATH="$BASE_PATH"
EOL
    echo -e "${GREEN}✅ Server config saved to ~/.solo-dev-server${NC}"
fi

# Load server config
source "$HOME/.solo-dev-server"

# Create project config
cat > ".deploy-config" << EOL
# Deployment config for $PROJECT_NAME
DEFAULT_PROJECT_NAME="$PROJECT_NAME"
DOMAIN="$DOMAIN"
DOCS_DIR="$DOCS_DIR"
SERVER_USER="$SERVER_USER"
SERVER_HOST="$SERVER_HOST"
SERVER_PATH="$BASE_PATH"
EOL

# Copy deployment script
cp "$HOME/.solo-dev-templates/deploy-template.sh" "./deploy.sh"
chmod +x deploy.sh

# Create nginx config
cat > "nginx-$PROJECT_NAME.conf" << EOL
# Nginx config for $PROJECT_NAME ($DOMAIN)
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    root $BASE_PATH/$PROJECT_NAME;
    index index.html;
    
    # SSL (update paths)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Clean URLs
    location / {
        try_files \$uri \$uri.html \$uri/ =404;
    }
    
    # Cache static assets
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json;
    
    # Logging
    access_log /var/log/nginx/$DOMAIN.access.log;
    error_log /var/log/nginx/$DOMAIN.error.log;
}
EOL

echo -e "${GREEN}✅ Project deployment setup complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Create your server directory: ssh $SERVER_USER@$SERVER_HOST 'mkdir -p $BASE_PATH/$PROJECT_NAME'"
echo "2. Copy nginx config: scp nginx-$PROJECT_NAME.conf $SERVER_USER@$SERVER_HOST:~/"
echo "3. Deploy: ./deploy.sh"
echo ""
echo -e "${BLUE}Files created:${NC}"
echo "- .deploy-config (project settings)"
echo "- deploy.sh (deployment script)"
echo "- nginx-$PROJECT_NAME.conf (nginx config)"
EOF

chmod +x "$TEMPLATE_DIR/setup-project.sh"

# Create the CLI tool
cat > "$TEMPLATE_DIR/solo-deploy" << 'EOF'
#!/bin/bash
# Solo Dev Deployment CLI
# Usage: solo-deploy [command] [options]

TEMPLATE_DIR="$HOME/.solo-dev-templates"

case "$1" in
    "new"|"init")
        echo "🎯 Initializing new project deployment..."
        "$TEMPLATE_DIR/setup-project.sh"
        ;;
    "deploy")
        if [ -f "deploy.sh" ]; then
            ./deploy.sh "$2"
        else
            echo "❌ No deploy.sh found. Run 'solo-deploy new' first"
        fi
        ;;
    "server")
        echo "🔧 Current server config:"
        if [ -f "$HOME/.solo-dev-server" ]; then
            cat "$HOME/.solo-dev-server"
        else
            echo "No server configured. Run 'solo-deploy new' to configure."
        fi
        ;;
    "help"|*)
        echo "Solo Dev Deployment Tool"
        echo ""
        echo "Commands:"
        echo "  new     - Setup deployment for new project"
        echo "  deploy  - Deploy current project"
        echo "  server  - Show server configuration"
        echo "  help    - Show this help"
        echo ""
        echo "Example workflow:"
        echo "  cd my-new-project/"
        echo "  solo-deploy new"
        echo "  solo-deploy deploy"
        ;;
esac
EOF

chmod +x "$TEMPLATE_DIR/solo-deploy"

# Add to PATH (if not already there)
if ! grep -q "$TEMPLATE_DIR" "$HOME/.bashrc" 2>/dev/null; then
    echo "export PATH=\"\$PATH:$TEMPLATE_DIR\"" >> "$HOME/.bashrc"
    echo -e "${YELLOW}📝 Added $TEMPLATE_DIR to your PATH${NC}"
fi

echo -e "${GREEN}✅ Solo Dev Deployment Template Created!${NC}"
echo ""
echo -e "${BLUE}🎯 Your new workflow for ANY project:${NC}"
echo "1. cd my-new-project/"
echo "2. solo-deploy new"
echo "3. solo-deploy deploy"
echo ""
echo -e "${YELLOW}Template files created in: $TEMPLATE_DIR${NC}"
echo "Restart your terminal or run: source ~/.bashrc"