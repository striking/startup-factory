#!/bin/bash
# HAL Health Check Script
# Checks if HAL is running and all services are healthy

set -e

# Configuration
PORT="${PORT:-4000}"
HOST="${PHX_HOST:-localhost}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${HOME}/Library/Logs/hal"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Track overall health
OVERALL_HEALTH=0

log_check() {
    echo -n -e "${BLUE}[CHECK]${NC} $1... "
}

log_pass() {
    echo -e "${GREEN}PASS${NC}"
}

log_fail() {
    echo -e "${RED}FAIL${NC}"
    OVERALL_HEALTH=1
}

log_warn() {
    echo -e "${YELLOW}WARN${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check 1: Process running
check_process() {
    log_check "HAL process"

    if pgrep -f "rel/hal/bin/hal" > /dev/null; then
        log_pass
        PID=$(pgrep -f "rel/hal/bin/hal" | head -1)
        log_info "  PID: ${PID}"
    elif pgrep -f "beam.*hal" > /dev/null; then
        log_pass
        PID=$(pgrep -f "beam.*hal" | head -1)
        log_info "  PID: ${PID} (BEAM)"
    else
        log_fail
        log_info "  HAL process not found"
    fi
}

# Check 2: Launchd service status
check_launchd() {
    log_check "Launchd service"

    SERVICE_NAME="com.hal.assistant"

    if launchctl list | grep -q "${SERVICE_NAME}"; then
        log_pass
        STATUS=$(launchctl list | grep "${SERVICE_NAME}" | awk '{print $1}')
        if [ "${STATUS}" = "-" ]; then
            log_info "  Status: Running"
        else
            log_info "  Status: Exit code ${STATUS}"
        fi
    else
        log_warn
        log_info "  Service not loaded (run deploy.sh to install)"
    fi
}

# Check 3: HTTP endpoint responding
check_http() {
    log_check "HTTP endpoint (${HOST}:${PORT})"

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${PORT}/" --connect-timeout 5 2>/dev/null || echo "000")

    if [ "${HTTP_STATUS}" = "200" ] || [ "${HTTP_STATUS}" = "302" ]; then
        log_pass
        log_info "  HTTP status: ${HTTP_STATUS}"
    else
        log_fail
        log_info "  HTTP status: ${HTTP_STATUS}"
    fi
}

# Check 4: LiveView dashboard
check_dashboard() {
    log_check "LiveView dashboard"

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${PORT}/dashboard" --connect-timeout 5 2>/dev/null || echo "000")

    if [ "${HTTP_STATUS}" = "200" ]; then
        log_pass
    else
        log_fail
        log_info "  Dashboard status: ${HTTP_STATUS}"
    fi
}

# Check 5: Phoenix Live Dashboard (for metrics)
check_live_dashboard() {
    log_check "Phoenix Live Dashboard"

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${PORT}/dev/dashboard" --connect-timeout 5 2>/dev/null || echo "000")

    if [ "${HTTP_STATUS}" = "200" ] || [ "${HTTP_STATUS}" = "302" ]; then
        log_pass
    else
        log_warn
        log_info "  Dev dashboard may be disabled in production"
    fi
}

# Check 6: Database connection
check_database() {
    log_check "Database connection"

    # Load environment
    if [ -f "${HOME}/.hal.env" ]; then
        set -a
        source "${HOME}/.hal.env"
        set +a
    fi

    DB_NAME="${DB_NAME:-hal_prod}"
    DB_HOST="${DB_HOST:-localhost}"
    DB_PORT="${DB_PORT:-5432}"
    DB_USER="${DB_USER:-$(whoami)}"

    # Parse DATABASE_URL if provided
    if [ -n "${DATABASE_URL}" ]; then
        DB_HOST=$(echo "${DATABASE_URL}" | sed -n 's|.*@\([^:]*\):.*|\1|p')
        DB_PORT=$(echo "${DATABASE_URL}" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
        DB_NAME=$(echo "${DATABASE_URL}" | sed -n 's|.*/\([^?]*\).*|\1|p')
    fi

    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1" > /dev/null 2>&1; then
        log_pass

        # Get session count
        SESSION_COUNT=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM sessions" 2>/dev/null | tr -d ' ' || echo "N/A")
        log_info "  Active sessions: ${SESSION_COUNT}"
    else
        log_fail
        log_info "  Could not connect to database ${DB_NAME}"
    fi
}

# Check 7: Claude Code CLI
check_claude_cli() {
    log_check "Claude Code CLI"

    if command -v claude &> /dev/null; then
        log_pass
        CLAUDE_VERSION=$(claude --version 2>&1 | head -1 || echo "unknown")
        log_info "  Version: ${CLAUDE_VERSION}"
    else
        log_warn
        log_info "  Claude CLI not in PATH (AI features may not work)"
    fi
}

# Check 8: Memory usage
check_memory() {
    log_check "Memory usage"

    if pgrep -f "beam.*hal" > /dev/null; then
        PID=$(pgrep -f "beam.*hal" | head -1)
        MEM=$(ps -o rss= -p "${PID}" 2>/dev/null | tr -d ' ')

        if [ -n "${MEM}" ]; then
            MEM_MB=$((MEM / 1024))
            log_pass
            log_info "  Memory: ${MEM_MB} MB"

            if [ "${MEM_MB}" -gt 500 ]; then
                log_info "  Warning: Memory usage is high (>500MB)"
            fi
        else
            log_warn
            log_info "  Could not determine memory usage"
        fi
    else
        log_warn
        log_info "  Process not running"
    fi
}

# Check 9: Log files
check_logs() {
    log_check "Log files"

    if [ -d "${LOG_DIR}" ]; then
        log_pass

        # Check for recent errors
        if [ -f "${LOG_DIR}/stderr.log" ]; then
            RECENT_ERRORS=$(tail -100 "${LOG_DIR}/stderr.log" 2>/dev/null | grep -c -i "error\|crash\|exception" || echo "0")
            if [ "${RECENT_ERRORS}" -gt 0 ]; then
                log_info "  Recent errors in stderr.log: ${RECENT_ERRORS}"
            fi
        fi

        # Check log size
        LOG_SIZE=$(du -sh "${LOG_DIR}" 2>/dev/null | cut -f1 || echo "N/A")
        log_info "  Log directory size: ${LOG_SIZE}"
    else
        log_warn
        log_info "  Log directory not found: ${LOG_DIR}"
    fi
}

# Check 10: Disk space
check_disk() {
    log_check "Disk space"

    DISK_USAGE=$(df -h "${PROJECT_ROOT}" | tail -1 | awk '{print $5}' | tr -d '%')

    if [ "${DISK_USAGE}" -lt 90 ]; then
        log_pass
        log_info "  Disk usage: ${DISK_USAGE}%"
    elif [ "${DISK_USAGE}" -lt 95 ]; then
        log_warn
        log_info "  Disk usage: ${DISK_USAGE}% (getting full)"
    else
        log_fail
        log_info "  Disk usage: ${DISK_USAGE}% (critical!)"
    fi
}

# Summary
print_summary() {
    echo ""
    echo "=========================================="
    if [ "${OVERALL_HEALTH}" -eq 0 ]; then
        echo -e "  ${GREEN}HAL HEALTH: HEALTHY${NC}"
    else
        echo -e "  ${RED}HAL HEALTH: UNHEALTHY${NC}"
    fi
    echo "=========================================="
    echo ""
    echo "Dashboard:  http://${HOST}:${PORT}/dashboard"
    echo "Logs:       ${LOG_DIR}"
    echo ""
}

# Run all checks
main() {
    echo ""
    echo "=========================================="
    echo "       HAL Health Check"
    echo "=========================================="
    echo ""

    check_process
    check_launchd
    check_http
    check_dashboard
    check_live_dashboard
    check_database
    check_claude_cli
    check_memory
    check_logs
    check_disk

    print_summary

    exit ${OVERALL_HEALTH}
}

# Handle arguments
case "${1:-}" in
    --quiet|-q)
        # Quiet mode - just exit code
        check_http > /dev/null 2>&1
        check_database > /dev/null 2>&1
        exit ${OVERALL_HEALTH}
        ;;
    --json|-j)
        # JSON output for monitoring systems
        check_process > /dev/null 2>&1
        check_http > /dev/null 2>&1
        check_database > /dev/null 2>&1

        echo "{\"healthy\": $([ ${OVERALL_HEALTH} -eq 0 ] && echo "true" || echo "false"), \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
        exit ${OVERALL_HEALTH}
        ;;
    --help|-h)
        echo "HAL Health Check Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --quiet, -q    Quiet mode (exit code only)"
        echo "  --json, -j     JSON output for monitoring"
        echo "  --help, -h     Show this help"
        echo ""
        echo "Exit codes:"
        echo "  0 = Healthy"
        echo "  1 = Unhealthy"
        ;;
    *)
        main
        ;;
esac
