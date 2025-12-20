# IDE Setup Guide

This guide helps you set up your development environment for pgGit development.

## Visual Studio Code

### Installation

1. Install VS Code from [code.visualstudio.com](https://code.visualstudio.com/)

2. Install recommended extensions:
   - Open command palette (`Ctrl+Shift+P`)
   - Run "Extensions: Show Recommended Extensions"
   - Install all recommended extensions

### Manual Extension Installation

```bash
code --install-extension ms-vscode.vscode-postgres
code --install-extension mtxr.sqltools
code --install-extension redhat.vscode-yaml
code --install-extension editorconfig.editorconfig
```

### Configuration

The project includes `.vscode/settings.json` with:
- PostgreSQL syntax highlighting
- SQL formatting with SQLTools
- Markdown linting
- EditorConfig integration
- Git integration settings

### Database Connection

1. Open SQLTools panel (`Ctrl+Shift+P` → "SQLTools: Add Connection")
2. Configure connection:
   - Name: `pgGit Development`
   - Server: `localhost`
   - Port: `5432`
   - Database: `pggit_dev`
   - Username: `postgres`
   - Ask for password: `true`

## JetBrains IDEs (IntelliJ IDEA, DataGrip)

### Setup

1. Install DataGrip or IntelliJ IDEA Ultimate
2. Open project directory
3. Configure PostgreSQL data source:
   - Go to Database panel
   - Add PostgreSQL data source
   - Configure connection details

### Recommended Plugins

- Database Tools and SQL
- PostgreSQL
- EditorConfig
- Git Integration

## Vim/Neovim

### SQL Support

```vim
" In ~/.vimrc or ~/.config/nvim/init.vim
autocmd BufRead,BufNewFile *.sql set filetype=pgsql
autocmd FileType pgsql setlocal expandtab shiftwidth=4
```

### Plugins

- [vim-pgsql](https://github.com/lifepillar/vim-pgsql) - PostgreSQL syntax
- [editorconfig-vim](https://github.com/editorconfig/editorconfig-vim)

## Emacs

### SQL Mode Configuration

```emacs-lisp
;; In ~/.emacs.d/init.el
(add-to-list 'auto-mode-alist '("\\.sql\\'" . sql-mode))

;; PostgreSQL specific
(add-hook 'sql-mode-hook
          (lambda ()
            (when (string-match "postgres" (or sql-product ""))
              (sql-set-product 'postgres))))

;; EditorConfig
(editorconfig-mode 1)
```

## Command Line Development

### Essential Tools

```bash
# Install PostgreSQL client
sudo apt-get install postgresql-client  # Ubuntu/Debian
brew install postgresql                 # macOS

# Install development tools
sudo apt-get install git curl wget jq   # Ubuntu/Debian
brew install git curl wget jq           # macOS
```

### Database Setup

```bash
# Create development database
createdb pggit_dev

# Install pgGit
psql -d pggit_dev -f sql/install.sql

# Run tests
psql -d pggit_dev -f tests/test-core.sql
```

## Testing Your Setup

### VS Code

1. Open a `.sql` file
2. Check syntax highlighting
3. Try formatting (`Shift+Alt+F`)
4. Connect to database via SQLTools

### Database Connection

```bash
# Test connection
psql -h localhost -p 5432 -U postgres -d pggit_dev -c "SELECT version();"

# Test pgGit installation
psql -d pggit_dev -c "SELECT * FROM pggit.health_check();"
```

### EditorConfig

```bash
# Verify EditorConfig works
editorconfig-checker

# Should show no issues
```

## Troubleshooting

### VS Code Issues

- **Extensions not installing**: Restart VS Code
- **SQL formatting not working**: Check SQLTools settings
- **Database connection fails**: Verify PostgreSQL is running

### Database Issues

- **Connection refused**: Start PostgreSQL service
- **Permission denied**: Check user permissions
- **pgGit not found**: Run installation script

### EditorConfig Issues

- **Not working**: Install EditorConfig plugin
- **Wrong formatting**: Check `.editorconfig` file

## Advanced Setup

### Remote Development

Use VS Code Remote SSH for remote development:

1. Install Remote SSH extension
2. Connect to remote server
3. Clone and develop remotely

### Docker Development

```bash
# Use provided docker setup
docker-compose up -d postgres
docker-compose exec postgres psql -U postgres -d pggit_dev
```

### Multi-Environment Setup

Configure multiple database connections for:
- Local development
- Testing
- Staging
- Production

## Getting Help

- [VS Code Documentation](https://code.visualstudio.com/docs)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [pgGit GitHub Issues](https://github.com/evoludigit/pgGit/issues)