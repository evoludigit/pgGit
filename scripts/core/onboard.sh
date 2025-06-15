#!/bin/bash

# pggit Onboarding Script
# Helps migrate existing databases to pggit

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-$USER}"
STRATEGY="dev-first"
BACKUP=true
DRY_RUN=false

# Print usage
usage() {
    cat << EOF
pggit Onboarding Assistant

Usage: $0 [OPTIONS] DATABASE_NAME

OPTIONS:
    -h, --host HOST          Database host (default: localhost)
    -p, --port PORT          Database port (default: 5432)
    -U, --user USER          Database user (default: current user)
    -s, --strategy STRATEGY  Onboarding strategy (default: dev-first)
                            Options: green-field, dev-first, shadow, hybrid
    --no-backup             Skip backup step (not recommended)
    --dry-run               Show what would be done without executing
    --help                  Show this help message

EXAMPLES:
    # Onboard development database
    $0 --strategy dev-first myapp_dev

    # Dry run for production
    $0 --strategy shadow --dry-run myapp_prod

    # Green field setup
    $0 --strategy green-field myapp_v2

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            DB_HOST="$2"
            shift 2
            ;;
        -p|--port)
            DB_PORT="$2"
            shift 2
            ;;
        -U|--user)
            DB_USER="$2"
            shift 2
            ;;
        -s|--strategy)
            STRATEGY="$2"
            shift 2
            ;;
        --no-backup)
            BACKUP=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            DB_NAME="$1"
            shift
            ;;
    esac
done

# Validate inputs
if [ -z "$DB_NAME" ]; then
    echo -e "${RED}Error: Database name is required${NC}"
    usage
fi

# Helper functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

execute_sql() {
    local sql="$1"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would execute:"
        echo "$sql"
    else
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$sql"
    fi
}

execute_sql_file() {
    local file="$1"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would execute SQL file: $file"
    else
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$file"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check PostgreSQL connection
    if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" > /dev/null 2>&1; then
        error "Cannot connect to database $DB_NAME"
    fi
    
    # Check PostgreSQL version
    PG_VERSION=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT current_setting('server_version_num')::int")
    
    if [ $PG_VERSION -lt 140000 ]; then
        error "PostgreSQL 14+ required (found: $PG_VERSION)"
    fi
    
    if [ $PG_VERSION -lt 170000 ]; then
        warning "PostgreSQL 17+ recommended for compression features"
    else
        success "PostgreSQL 17+ detected - full compression support available"
    fi
    
    # Check if pggit is already installed
    PGGIT_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pggit')")
    
    if [ "$PGGIT_EXISTS" = "t" ]; then
        warning "pggit is already installed in $DB_NAME"
    fi
    
    success "Prerequisites check completed"
}

# Backup database
backup_database() {
    if [ "$BACKUP" = true ]; then
        log "Creating backup..."
        BACKUP_FILE="${DB_NAME}_backup_$(date +%Y%m%d_%H%M%S).sql"
        
        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}[DRY RUN]${NC} Would create backup: $BACKUP_FILE"
        else
            pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" > "$BACKUP_FILE"
            success "Backup created: $BACKUP_FILE"
        fi
    else
        warning "Skipping backup (not recommended)"
    fi
}

# Green field strategy
strategy_green_field() {
    log "Executing green field strategy..."
    
    # Install pggit
    execute_sql "CREATE EXTENSION IF NOT EXISTS pggit;"
    
    # Create main schema
    execute_sql "CREATE SCHEMA IF NOT EXISTS main;"
    
    # Set search path
    execute_sql "ALTER DATABASE $DB_NAME SET search_path = main, pggit, public;"
    
    success "Green field setup completed"
    
    cat << EOF

${GREEN}Next steps:${NC}
1. Create your tables in the 'main' schema
2. Use pggit.create_branch() for feature development
3. Check out the examples:
   - SELECT pggit.create_data_branch('feature/my-feature', 'main', true);
   - SELECT pggit.checkout_branch('feature/my-feature');

EOF
}

# Dev-first strategy
strategy_dev_first() {
    log "Executing dev-first strategy..."
    
    # Install pggit
    execute_sql "CREATE EXTENSION IF NOT EXISTS pggit;"
    
    # Check current schema
    SCHEMA_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'")
    
    if [ $SCHEMA_COUNT -gt 0 ]; then
        log "Found $SCHEMA_COUNT tables in public schema"
        
        # Rename public to main
        execute_sql "ALTER SCHEMA public RENAME TO main;"
        execute_sql "CREATE SCHEMA public;" # Recreate for compatibility
        
        # Import existing schema
        execute_sql "SELECT pggit.import_existing_schema('main');"
    else
        log "No existing tables found, creating main schema"
        execute_sql "CREATE SCHEMA IF NOT EXISTS main;"
    fi
    
    # Create development branches
    execute_sql "SELECT pggit.create_branch('staging', 'main');"
    execute_sql "SELECT pggit.create_branch('development', 'main');"
    
    success "Dev-first setup completed"
    
    # Show summary
    execute_sql "SELECT * FROM pggit.list_branches();"
}

# Shadow mode strategy
strategy_shadow() {
    log "Executing shadow mode strategy..."
    
    warning "Shadow mode: pggit will track changes without creating branches"
    
    # Install pggit
    execute_sql "CREATE EXTENSION IF NOT EXISTS pggit;"
    
    # Import in shadow mode
    execute_sql "SELECT pggit.import_existing_schema('public', shadow_mode := true);"
    
    # Create monitoring views
    execute_sql "CREATE OR REPLACE VIEW pggit_health AS 
        SELECT 
            (SELECT COUNT(*) FROM pggit.objects) as tracked_objects,
            (SELECT COUNT(*) FROM pggit.branches) as branches,
            (SELECT pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename)))) as total_size
        FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');"
    
    success "Shadow mode setup completed"
    
    cat << EOF

${GREEN}Shadow mode active:${NC}
- pggit is tracking changes but not interfering
- Monitor with: SELECT * FROM pggit_health;
- When ready, activate branches with:
  SELECT pggit.activate_branching();

EOF
}

# Hybrid strategy
strategy_hybrid() {
    log "Executing hybrid strategy..."
    
    # Install pggit
    execute_sql "CREATE EXTENSION IF NOT EXISTS pggit;"
    
    # Create new schema for pggit-managed objects
    execute_sql "CREATE SCHEMA IF NOT EXISTS main_v2;"
    
    # Track the new schema
    execute_sql "SELECT pggit.track_schema('main_v2');"
    
    # Create migration helper
    execute_sql "
    CREATE OR REPLACE FUNCTION migrate_table_to_pggit(table_name TEXT)
    RETURNS TEXT AS \$\$
    BEGIN
        EXECUTE format('ALTER TABLE public.%I SET SCHEMA main_v2', table_name);
        EXECUTE format('CREATE VIEW public.%I AS SELECT * FROM main_v2.%I', table_name, table_name);
        RETURN 'Migrated: ' || table_name;
    END;
    \$\$ LANGUAGE plpgsql;"
    
    success "Hybrid setup completed"
    
    cat << EOF

${GREEN}Hybrid mode active:${NC}
- Existing tables remain in 'public' schema
- New development happens in 'main_v2' schema
- Migrate tables individually:
  SELECT migrate_table_to_pggit('your_table_name');

EOF
}

# Main execution
main() {
    echo -e "${BLUE}pggit Onboarding Assistant${NC}"
    echo "================================"
    echo "Database: $DB_NAME"
    echo "Host: $DB_HOST:$DB_PORT"
    echo "Strategy: $STRATEGY"
    echo "Dry Run: $DRY_RUN"
    echo "================================"
    echo
    
    # Run checks
    check_prerequisites
    
    # Create backup
    backup_database
    
    # Execute strategy
    case $STRATEGY in
        green-field)
            strategy_green_field
            ;;
        dev-first)
            strategy_dev_first
            ;;
        shadow)
            strategy_shadow
            ;;
        hybrid)
            strategy_hybrid
            ;;
        *)
            error "Unknown strategy: $STRATEGY"
            ;;
    esac
    
    # Final summary
    if [ "$DRY_RUN" = false ]; then
        log "Generating onboarding report..."
        
        cat << EOF > "pggit_onboarding_${DB_NAME}_$(date +%Y%m%d).txt"
pggit Onboarding Report
======================
Database: $DB_NAME
Date: $(date)
Strategy: $STRATEGY

Objects Tracked: $(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM pggit.objects" 2>/dev/null || echo "0")
Branches Created: $(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM pggit.branches" 2>/dev/null || echo "0")

Next Steps:
1. Test branch creation: SELECT pggit.create_branch('test/onboarding', 'main');
2. Review documentation: https://github.com/evoludigit/pggit/docs
3. Train your team on pggit workflows

For support: onboarding@pggit.com
EOF
        
        success "Onboarding completed! Report saved to: pggit_onboarding_${DB_NAME}_$(date +%Y%m%d).txt"
    else
        success "Dry run completed. Re-run without --dry-run to execute."
    fi
}

# Run main function
main