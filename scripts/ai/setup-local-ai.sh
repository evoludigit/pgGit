#!/bin/bash
# pggit Local AI Setup Script
# Sets up local LLM infrastructure for AI-powered migrations

set -e

echo "🤖 Setting up pggit Local AI Infrastructure"
echo "============================================="

# Configuration
MODELS_DIR="/models"
LLAMA_CPP_DIR="/usr/local/src/llama.cpp"
MODEL_URL="https://huggingface.co/TheBloke/CodeLlama-7B-SQL-GGUF/resolve/main/codellama-7b-sql.Q4_K_M.gguf"
MODEL_FILE="codellama-7b-sql.gguf"

# Check if running as root for system installations
if [[ $EUID -eq 0 ]]; then
    echo "⚠️  Running as root - will install system-wide"
    SYSTEM_INSTALL=true
else
    echo "👤 Running as user - will install locally"
    SYSTEM_INSTALL=false
    MODELS_DIR="$HOME/models"
    LLAMA_CPP_DIR="$HOME/llama.cpp"
fi

# Create directories
echo "📁 Creating directories..."
mkdir -p "$MODELS_DIR"
mkdir -p "$(dirname $LLAMA_CPP_DIR)"

# Install system dependencies
echo "📦 Installing system dependencies..."
if command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    if [[ $SYSTEM_INSTALL == true ]]; then
        apt-get update
        apt-get install -y build-essential python3-dev python3-pip git curl wget
    else
        echo "Please run: sudo apt-get install build-essential python3-dev python3-pip git curl wget"
    fi
elif command -v yum &> /dev/null; then
    # CentOS/RHEL
    if [[ $SYSTEM_INSTALL == true ]]; then
        yum groupinstall -y "Development Tools"
        yum install -y python3-devel python3-pip git curl wget
    else
        echo "Please run: sudo yum groupinstall 'Development Tools' && sudo yum install python3-devel python3-pip git curl wget"
    fi
elif command -v pacman &> /dev/null; then
    # Arch Linux
    if [[ $SYSTEM_INSTALL == true ]]; then
        pacman -S --noconfirm base-devel python python-pip git curl wget
    else
        echo "Please run: sudo pacman -S base-devel python python-pip git curl wget"
    fi
else
    echo "⚠️  Unknown package manager. Please install: build tools, python3-dev, pip, git, curl, wget"
fi

# Install Python dependencies
echo "🐍 Installing Python dependencies..."
pip3 install --user sentence-transformers numpy psycopg2-binary torch torchvision torchaudio

# Install/Build llama.cpp
echo "🦙 Setting up llama.cpp..."
if [[ ! -d "$LLAMA_CPP_DIR" ]]; then
    git clone https://github.com/ggerganov/llama.cpp "$LLAMA_CPP_DIR"
fi

cd "$LLAMA_CPP_DIR"
git pull
make clean
make -j$(nproc)

# Create symlink for system access
if [[ $SYSTEM_INSTALL == true ]]; then
    ln -sf "$LLAMA_CPP_DIR/llama" /usr/local/bin/llama
else
    # Add to user PATH
    echo "export PATH=\"$LLAMA_CPP_DIR:\$PATH\"" >> ~/.bashrc
    export PATH="$LLAMA_CPP_DIR:$PATH"
fi

# Download model if not exists
echo "📥 Downloading CodeLlama-SQL model..."
if [[ ! -f "$MODELS_DIR/$MODEL_FILE" ]]; then
    echo "⏬ This will download ~4GB model file..."
    wget -O "$MODELS_DIR/$MODEL_FILE" "$MODEL_URL"
    echo "✅ Model downloaded to $MODELS_DIR/$MODEL_FILE"
else
    echo "✅ Model already exists at $MODELS_DIR/$MODEL_FILE"
fi

# Test model
echo "🧪 Testing model..."
cd "$LLAMA_CPP_DIR"
echo "Testing inference..." | timeout 30s ./llama -m "$MODELS_DIR/$MODEL_FILE" -p "CREATE TABLE" -n 10 --temp 0.1 || echo "⚠️  Model test may have timed out (normal for first run)"

# PostgreSQL Extension Setup
echo "🐘 Setting up PostgreSQL extensions..."

# Check if PostgreSQL is running
if ! pg_isready &> /dev/null; then
    echo "⚠️  PostgreSQL not running. Please start it first."
    echo "   sudo systemctl start postgresql"
    exit 1
fi

# Install required extensions
psql -c "CREATE EXTENSION IF NOT EXISTS plpython3u;" || echo "⚠️  plpython3u not available - install postgresql-plpython3"
psql -c "CREATE EXTENSION IF NOT EXISTS vector;" || echo "⚠️  pgvector not available - install from https://github.com/pgvector/pgvector"

# Load pggit AI functions
if [[ -f "sql/033_local_llm_integration.sql" ]]; then
    echo "📚 Loading pggit AI functions..."
    psql -f sql/033_local_llm_integration.sql
else
    echo "⚠️  pggit AI SQL file not found. Make sure you're in the pggit directory."
fi

# Create configuration file
echo "⚙️  Creating configuration..."
cat > "$MODELS_DIR/pggit-ai.conf" << EOF
# pggit AI Configuration
MODEL_PATH=$MODELS_DIR/$MODEL_FILE
LLAMA_CPP_PATH=$LLAMA_CPP_DIR/llama
MODELS_DIR=$MODELS_DIR
EOF

# Test full integration
echo "🧪 Testing full AI integration..."
psql -c "SELECT * FROM pggit.test_llm_integration();" || echo "⚠️  Integration test failed - check logs"

echo ""
echo "🎉 pggit Local AI Setup Complete!"
echo "=================================="
echo ""
echo "Configuration:"
echo "  Model: $MODELS_DIR/$MODEL_FILE"
echo "  llama.cpp: $LLAMA_CPP_DIR/llama"
echo "  Config: $MODELS_DIR/pggit-ai.conf"
echo ""
echo "Next steps:"
echo "1. Test AI migration: SELECT * FROM pggit.test_llm_integration();"
echo "2. Try analyzing a migration:"
echo "   SELECT * FROM pggit.analyze_migration_with_llm("
echo "     'CREATE TABLE users (id SERIAL PRIMARY KEY);',"
echo "     'flyway',"
echo "     'V1__create_users.sql'"
echo "   );"
echo ""
echo "3. For batch migrations:"
echo "   SELECT * FROM pggit.ai_migrate_batch('[{...}]'::jsonb, 'flyway');"
echo ""
echo "🔧 Troubleshooting:"
echo "- If model is slow: Use smaller model (3B instead of 7B)"
echo "- If out of memory: Reduce context size or use quantized model"
echo "- If plpython3u missing: sudo apt install postgresql-plpython3-XX"
echo "- If pgvector missing: Install from https://github.com/pgvector/pgvector"
echo ""
echo "Happy AI-powered migrations! 🚀"