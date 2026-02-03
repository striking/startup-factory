#!/bin/bash
# HAL Database Backup Script
# Creates daily PostgreSQL backups with 7-day rotation

set -e

# Configuration
BACKUP_DIR="${HOME}/backups/hal"
BACKUP_RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/hal_backup_${TIMESTAMP}.sql.gz"

# Database configuration
# These can be overridden by environment variables or .env file
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
    # Extract components from DATABASE_URL
    # Format: postgres://user:password@host:port/database
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

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

create_backup() {
    log_info "Starting backup of database: ${DB_NAME}"
    log_info "Backup file: ${BACKUP_FILE}"

    # Set password for pg_dump if available
    if [ -n "${DB_PASSWORD}" ]; then
        export PGPASSWORD="${DB_PASSWORD}"
    fi

    # Create backup
    pg_dump \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        --format=plain \
        --no-owner \
        --no-privileges \
        --verbose \
        2>&1 | gzip > "${BACKUP_FILE}"

    # Unset password
    unset PGPASSWORD

    # Verify backup was created
    if [ -f "${BACKUP_FILE}" ] && [ -s "${BACKUP_FILE}" ]; then
        BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        log_success "Backup created successfully: ${BACKUP_FILE} (${BACKUP_SIZE})"
    else
        log_error "Backup failed or file is empty"
        rm -f "${BACKUP_FILE}"
        exit 1
    fi
}

rotate_backups() {
    log_info "Rotating old backups (keeping last ${BACKUP_RETENTION_DAYS} days)..."

    # Find and delete backups older than retention period
    DELETED_COUNT=$(find "${BACKUP_DIR}" -name "hal_backup_*.sql.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -print -delete | wc -l | tr -d ' ')

    if [ "${DELETED_COUNT}" -gt 0 ]; then
        log_info "Deleted ${DELETED_COUNT} old backup(s)"
    else
        log_info "No old backups to delete"
    fi

    # List remaining backups
    log_info "Current backups:"
    ls -lh "${BACKUP_DIR}"/hal_backup_*.sql.gz 2>/dev/null || log_info "No backups found"
}

verify_backup() {
    log_info "Verifying backup integrity..."

    # Test gzip integrity
    if gzip -t "${BACKUP_FILE}" 2>/dev/null; then
        log_success "Backup file integrity verified"
    else
        log_error "Backup file is corrupted"
        exit 1
    fi

    # Check backup contains expected tables
    TABLES=$(zcat "${BACKUP_FILE}" | grep -c "CREATE TABLE" || echo "0")
    log_info "Backup contains ${TABLES} table definitions"

    if [ "${TABLES}" -lt 1 ]; then
        log_warning "Backup may be incomplete - no tables found"
    fi
}

show_usage() {
    echo "HAL Database Backup Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  backup    Create a new backup (default)"
    echo "  rotate    Only rotate old backups"
    echo "  list      List all backups"
    echo "  verify    Verify the latest backup"
    echo ""
    echo "Configuration (via environment or ~/.hal.env):"
    echo "  DATABASE_URL    PostgreSQL connection URL"
    echo "  DB_NAME         Database name (default: hal_prod)"
    echo "  DB_HOST         Database host (default: localhost)"
    echo "  DB_PORT         Database port (default: 5432)"
    echo "  DB_USER         Database user (default: current user)"
    echo ""
    echo "Backups are stored in: ${BACKUP_DIR}"
    echo "Retention: ${BACKUP_RETENTION_DAYS} days"
}

list_backups() {
    log_info "Available backups in ${BACKUP_DIR}:"
    echo ""

    if ls "${BACKUP_DIR}"/hal_backup_*.sql.gz 1>/dev/null 2>&1; then
        ls -lhtr "${BACKUP_DIR}"/hal_backup_*.sql.gz
        echo ""
        TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
        BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/hal_backup_*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
        log_info "Total: ${BACKUP_COUNT} backup(s), ${TOTAL_SIZE}"
    else
        log_warning "No backups found"
    fi
}

verify_latest() {
    LATEST_BACKUP=$(ls -t "${BACKUP_DIR}"/hal_backup_*.sql.gz 2>/dev/null | head -1)

    if [ -n "${LATEST_BACKUP}" ]; then
        BACKUP_FILE="${LATEST_BACKUP}"
        verify_backup
    else
        log_error "No backups found to verify"
        exit 1
    fi
}

# Main
case "${1:-backup}" in
    backup)
        create_backup
        verify_backup
        rotate_backups
        ;;
    rotate)
        rotate_backups
        ;;
    list)
        list_backups
        ;;
    verify)
        verify_latest
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac

log_success "Backup operation completed"
