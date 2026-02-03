#!/bin/bash
# HAL Database Restore Script
# Restores PostgreSQL database from backup

set -e

# Configuration
BACKUP_DIR="${HOME}/backups/hal"

# Database configuration
DB_NAME="${DB_NAME:-hal_prod}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-$(whoami)}"

# Load environment file if exists
if [ -f "${HOME}/.hal.env" ]; then
    set -a
    source "${HOME}/.hal.env"
    set +a
fi

# Parse DATABASE_URL if provided
if [ -n "${DATABASE_URL}" ]; then
    DB_USER=$(echo "${DATABASE_URL}" | sed -n 's|.*://\([^:]*\):.*|\1|p')
    DB_PASSWORD=$(echo "${DATABASE_URL}" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
    DB_HOST=$(echo "${DATABASE_URL}" | sed -n 's|.*@\([^:]*\):.*|\1|p')
    DB_PORT=$(echo "${DATABASE_URL}" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    DB_NAME=$(echo "${DATABASE_URL}" | sed -n 's|.*/\([^?]*\).*|\1|p')
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

show_usage() {
    echo "HAL Database Restore Script"
    echo ""
    echo "Usage: $0 [backup_file]"
    echo ""
    echo "Arguments:"
    echo "  backup_file   Path to backup file (optional)"
    echo "                If not provided, uses the latest backup"
    echo ""
    echo "Options:"
    echo "  --list        List available backups"
    echo "  --latest      Use the latest backup (default)"
    echo "  --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Restore from latest backup"
    echo "  $0 --list                             # List all backups"
    echo "  $0 /path/to/hal_backup_20260128.sql.gz  # Restore specific backup"
    echo ""
    echo "Configuration (via environment or ~/.hal.env):"
    echo "  DATABASE_URL    PostgreSQL connection URL"
    echo "  DB_NAME         Database name (default: hal_prod)"
    echo "  DB_HOST         Database host (default: localhost)"
    echo ""
    echo "WARNING: Restore will DROP and recreate the database!"
}

list_backups() {
    log_info "Available backups in ${BACKUP_DIR}:"
    echo ""

    if ls "${BACKUP_DIR}"/hal_backup_*.sql.gz 1>/dev/null 2>&1; then
        ls -lhtr "${BACKUP_DIR}"/hal_backup_*.sql.gz
        echo ""
        LATEST=$(ls -t "${BACKUP_DIR}"/hal_backup_*.sql.gz 2>/dev/null | head -1)
        log_info "Latest: $(basename "${LATEST}")"
    else
        log_warning "No backups found in ${BACKUP_DIR}"
    fi
}

get_latest_backup() {
    LATEST=$(ls -t "${BACKUP_DIR}"/hal_backup_*.sql.gz 2>/dev/null | head -1)

    if [ -z "${LATEST}" ]; then
        log_error "No backups found in ${BACKUP_DIR}"
        exit 1
    fi

    echo "${LATEST}"
}

verify_backup_file() {
    local backup_file="$1"

    if [ ! -f "${backup_file}" ]; then
        log_error "Backup file not found: ${backup_file}"
        exit 1
    fi

    log_info "Verifying backup file integrity..."
    if gzip -t "${backup_file}" 2>/dev/null; then
        log_success "Backup file integrity verified"
    else
        log_error "Backup file is corrupted: ${backup_file}"
        exit 1
    fi
}

confirm_restore() {
    local backup_file="$1"

    echo ""
    echo "=============================================="
    echo "           DATABASE RESTORE"
    echo "=============================================="
    echo ""
    echo "Backup:   $(basename "${backup_file}")"
    echo "Database: ${DB_NAME}"
    echo "Host:     ${DB_HOST}:${DB_PORT}"
    echo ""
    echo "WARNING: This will DROP all existing data!"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [ "${confirm}" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi
}

stop_hal_service() {
    log_info "Stopping HAL service..."

    SERVICE_NAME="com.hal.assistant"
    LAUNCHD_PLIST="${HOME}/Library/LaunchAgents/${SERVICE_NAME}.plist"

    if launchctl list | grep -q "${SERVICE_NAME}"; then
        launchctl unload "${LAUNCHD_PLIST}" 2>/dev/null || true
        log_success "Service stopped"
        sleep 2
    else
        log_info "Service was not running"
    fi
}

restore_database() {
    local backup_file="$1"

    log_info "Starting database restore from: $(basename "${backup_file}")"

    # Set password if available
    if [ -n "${DB_PASSWORD}" ]; then
        export PGPASSWORD="${DB_PASSWORD}"
    fi

    # Drop and recreate database
    log_info "Dropping existing database..."
    dropdb -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" --if-exists "${DB_NAME}" 2>/dev/null || true

    log_info "Creating new database..."
    createdb -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" "${DB_NAME}"

    # Restore from backup
    log_info "Restoring data..."
    zcat "${backup_file}" | psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -q

    # Unset password
    unset PGPASSWORD

    log_success "Database restored successfully"
}

verify_restore() {
    log_info "Verifying restore..."

    if [ -n "${DB_PASSWORD}" ]; then
        export PGPASSWORD="${DB_PASSWORD}"
    fi

    # Check tables exist
    TABLES=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'" | tr -d ' ')

    unset PGPASSWORD

    if [ "${TABLES}" -gt 0 ]; then
        log_success "Restore verified: ${TABLES} tables found"
    else
        log_warning "No tables found after restore - verify the backup was complete"
    fi
}

start_hal_service() {
    log_info "Starting HAL service..."

    SERVICE_NAME="com.hal.assistant"
    LAUNCHD_PLIST="${HOME}/Library/LaunchAgents/${SERVICE_NAME}.plist"

    if [ -f "${LAUNCHD_PLIST}" ]; then
        launchctl load "${LAUNCHD_PLIST}"
        log_success "Service started"
    else
        log_warning "Service plist not found, skipping service start"
        log_info "Run deploy.sh to install the service"
    fi
}

# Main
case "${1:-}" in
    --help|-h|help)
        show_usage
        exit 0
        ;;
    --list|list)
        list_backups
        exit 0
        ;;
    --latest|"")
        BACKUP_FILE=$(get_latest_backup)
        ;;
    *)
        if [ -f "$1" ]; then
            BACKUP_FILE="$1"
        else
            log_error "File not found: $1"
            exit 1
        fi
        ;;
esac

# Perform restore
verify_backup_file "${BACKUP_FILE}"
confirm_restore "${BACKUP_FILE}"
stop_hal_service
restore_database "${BACKUP_FILE}"
verify_restore
start_hal_service

echo ""
log_success "Restore completed successfully"
echo ""
echo "Next steps:"
echo "  1. Verify HAL is running: ${HOME}/dev/concepts/hal/scripts/health_check.sh"
echo "  2. Check the dashboard: http://localhost:4000/dashboard"
echo ""
