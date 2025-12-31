# Use Ubuntu as base for better compatibility with PostgreSQL tools
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Install PostgreSQL client and development tools
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        postgresql-client-14 \
        postgresql-server-dev-14 \
        build-essential \
        make \
        gcc \
        git \
        curl \
        jq \
        vim \
        less \
        sudo \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install uv (modern Python package installer)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /home/vscode/.bashrc

# Install Python and set up virtual environment
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        python3.11 \
        python3.11-venv \
        python3-pip \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Create workspace directory
RUN mkdir -p /workspace && chown vscode:vscode /workspace

# Switch to non-root user
USER vscode

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
