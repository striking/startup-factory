#!/bin/bash
# HAL Deployment Script
# Builds a release and deploys it to the local Mac mini

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_NAME="hal"
SERVICE_NAME="com.hal.assistant"
LAUNCHD_PLIST="${HOME}/Library/LaunchAgents/${SERVICE_NAME}.plist"
LOG_DIR="${HOME}/Library/Logs/hal"
BACKUP_DIR="${HOME}/backups/hal"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Elixir
    if ! command -v elixir &> /dev/null; then
        log_error "Elixir is not installed. Install with: brew install elixir"
        exit 1
    fi

    # Check Mix
    if ! command -v mix &> /dev/null; then
        log_error "Mix is not available"
        exit 1
    fi

    # Check PostgreSQL
    if ! command -v psql &> /dev/null; then
        log_error "PostgreSQL is not installed. Install with: brew install postgresql@16"
        exit 1
    fi

    # Check Claude Code CLI
    if ! command -v claude &> /dev/null; then
        log_warning "Claude Code CLI not found in PATH. Some features may not work."
        log_warning "Install with: npm install -g @anthropic-ai/claude-code"
    fi

    # Check environment file
    if [ ! -f "${PROJECT_ROOT}/.env" ] && [ ! -f "${HOME}/.hal.env" ]; then
        log_warning "No .env file found. Make sure environment variables are set."
    fi

    log_success "Prerequisites check passed"
}

stop_service() {
    log_info "Stopping existing HAL service..."

    if launchctl list | grep -q "${SERVICE_NAME}"; then
        launchctl unload "${LAUNCHD_PLIST}" 2>/dev/null || true
        log_success "Service stopped"
    else
        log_info "Service was not running"
    fi

    # Also try to stop any running release
    if [ -f "${PROJECT_ROOT}/_build/prod/rel/${RELEASE_NAME}/bin/${RELEASE_NAME}" ]; then
        "${PROJECT_ROOT}/_build/prod/rel/${RELEASE_NAME}/bin/${RELEASE_NAME}" stop 2>/dev/null || true
    fi

    # Wait for process to fully stop
    sleep 2
}

build_release() {
    log_info "Building production release..."

    cd "${PROJECT_ROOT}"

    # Clean previous build
    log_info "Cleaning previous build..."
    rm -rf _build/prod

    # Fetch dependencies
    log_info "Fetching dependencies..."
    MIX_ENV=prod mix deps.get --only prod

    # Compile assets (if applicable)
    if [ -f "assets/package.json" ]; then
        log_info "Compiling assets..."
        cd assets && npm install && cd ..
        MIX_ENV=prod mix assets.deploy 2>/dev/null || true
    fi

    # Compile
    log_info "Compiling project..."
    MIX_ENV=prod mix compile

    # Build release
    log_info "Building release..."
    MIX_ENV=prod mix release --overwrite

    log_success "Release built successfully"
}

run_migrations() {
    log_info "Running database migrations..."

    cd "${PROJECT_ROOT}"

    # Run migrations using the release
    "${PROJECT_ROOT}/_build/prod/rel/${RELEASE_NAME}/bin/${RELEASE_NAME}" eval "Hal.Release.migrate()"

    log_success "Migrations completed"
}

setup_directories() {
    log_info "Setting up directories..."

    # Create log directory
    mkdir -p "${LOG_DIR}"

    # Create backup directory
    mkdir -p "${BACKUP_DIR}"

    log_success "Directories created"
}

install_service() {
    log_info "Installing launchd service..."

    # Get current user
    CURRENT_USER=$(whoami)

    # Create plist from template
    cat > "${LAUNCHD_PLIST}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_NAME}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${PROJECT_ROOT}/_build/prod/rel/${RELEASE_NAME}/bin/${RELEASE_NAME}</string>
        <string>start</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>ThrottleInterval</key>
    <integer>10</integer>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stderr.log</string>

    <key>WorkingDirectory</key>
    <string>${PROJECT_ROOT}</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>/Users/${CURRENT_USER}</string>
        <key>PATH</key>
        <string>/Users/${CURRENT_USER}/.local/bin:/Users/${CURRENT_USER}/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>LANG</key>
        <string>en_US.UTF-8</string>
        <key>PHX_SERVER</key>
        <string>true</string>
    </dict>

    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>65536</integer>
    </dict>

    <key>HardResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>65536</integer>
    </dict>
</dict>
</plist>
EOF

    log_success "Service plist installed at ${LAUNCHD_PLIST}"
}

start_service() {
    log_info "Starting HAL service..."

    launchctl load "${LAUNCHD_PLIST}"

    # Wait for service to start
    sleep 3

    log_success "Service started"
}

health_check() {
    log_info "Running health check..."

    "${SCRIPT_DIR}/health_check.sh"

    if [ $? -eq 0 ]; then
        log_success "Health check passed"
    else
        log_error "Health check failed"
        log_warning "Check logs at ${LOG_DIR}"
        exit 1
    fi
}

show_status() {
    echo ""
    echo "=========================================="
    echo "       HAL Deployment Complete"
    echo "=========================================="
    echo ""
    echo "Release:        ${PROJECT_ROOT}/_build/prod/rel/${RELEASE_NAME}"
    echo "Service:        ${SERVICE_NAME}"
    echo "Logs:           ${LOG_DIR}"
    echo "Dashboard:      http://localhost:${PORT:-4000}/dashboard"
    echo ""
    echo "Commands:"
    echo "  View logs:    tail -f ${LOG_DIR}/stdout.log"
    echo "  Stop:         launchctl unload ${LAUNCHD_PLIST}"
    echo "  Start:        launchctl load ${LAUNCHD_PLIST}"
    echo "  Status:       launchctl list | grep ${SERVICE_NAME}"
    echo "  Health:       ${SCRIPT_DIR}/health_check.sh"
    echo ""
}

# Main deployment flow
main() {
    echo ""
    echo "=========================================="
    echo "       HAL Deployment Script"
    echo "=========================================="
    echo ""

    check_prerequisites
    stop_service
    build_release
    setup_directories
    run_migrations
    install_service
    start_service
    health_check
    show_status
}

# Parse arguments
case "${1:-deploy}" in
    deploy)
        main
        ;;
    build)
        check_prerequisites
        build_release
        ;;
    stop)
        stop_service
        ;;
    start)
        start_service
        ;;
    restart)
        stop_service
        start_service
        health_check
        ;;
    status)
        if launchctl list | grep -q "${SERVICE_NAME}"; then
            log_success "HAL service is running"
            "${SCRIPT_DIR}/health_check.sh"
        else
            log_warning "HAL service is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {deploy|build|stop|start|restart|status}"
        exit 1
        ;;
esac
