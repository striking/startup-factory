#!/bin/bash
# =============================================================================
# HAL Assistant - First-Time Setup Script
# =============================================================================
#
# This script sets up HAL for the first time on a new system.
#
# Usage:
#   ./scripts/setup.sh
#
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# =============================================================================
# Prerequisites Check
# =============================================================================

print_header "Checking Prerequisites"

MISSING_DEPS=0

# Check Erlang/OTP
if check_command "erl"; then
    ERL_VERSION=$(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell)
    print_info "Erlang/OTP version: $ERL_VERSION"
else
    print_error "Erlang/OTP is required. Install with: brew install erlang"
    MISSING_DEPS=1
fi

# Check Elixir
if check_command "elixir"; then
    ELIXIR_VERSION=$(elixir --version | grep Elixir | awk '{print $2}')
    print_info "Elixir version: $ELIXIR_VERSION"
else
    print_error "Elixir is required. Install with: brew install elixir"
    MISSING_DEPS=1
fi

# Check PostgreSQL
if check_command "psql"; then
    PG_VERSION=$(psql --version | awk '{print $3}')
    print_info "PostgreSQL version: $PG_VERSION"
else
    print_error "PostgreSQL is required. Install with: brew install postgresql@15"
    MISSING_DEPS=1
fi

# Check Claude Code CLI
if check_command "claude"; then
    print_success "Claude Code CLI is installed"
    print_info "Checking authentication..."
    if claude auth status &> /dev/null; then
        print_success "Claude Code is authenticated"
    else
        print_warning "Claude Code is not authenticated"
        print_info "Run: claude auth login"
    fi
else
    print_error "Claude Code CLI is required. Install from: https://www.anthropic.com/claude-code"
    MISSING_DEPS=1
fi

if [ $MISSING_DEPS -eq 1 ]; then
    print_error "Missing dependencies. Please install them and run setup again."
    exit 1
fi

# =============================================================================
# Environment Configuration
# =============================================================================

print_header "Environment Configuration"

cd "$PROJECT_ROOT"

# Check if .env.production exists
if [ -f ".env.production" ]; then
    print_success ".env.production file exists"
else
    print_warning ".env.production not found"
    print_info "Copying from .env.example..."
    cp .env.example .env.production
    print_success "Created .env.production"
fi

# Check if ~/.hal.env exists
if [ -f "$HOME/.hal.env" ]; then
    print_success "~/.hal.env exists"
else
    print_warning "~/.hal.env not found"
    print_info "Creating from .env.production..."
    cp .env.production "$HOME/.hal.env"
    print_success "Created ~/.hal.env"
fi

# Generate SECRET_KEY_BASE if needed
if grep -q "GENERATE_A_SECURE_SECRET_KEY" "$HOME/.hal.env"; then
    print_info "Generating SECRET_KEY_BASE..."
    SECRET_KEY=$(mix phx.gen.secret)
    # Use @ as delimiter to avoid / conflicts
    sed -i.bak "s@GENERATE_A_SECURE_SECRET_KEY_WITH_MIX_PHX_GEN_SECRET@$SECRET_KEY@g" "$HOME/.hal.env"
    rm "$HOME/.hal.env.bak"
    print_success "Generated SECRET_KEY_BASE"
fi

print_warning "IMPORTANT: Edit ~/.hal.env and add your API tokens:"
print_info "  - TELEGRAM_BOT_TOKEN"
print_info "  - SLACK_BOT_TOKEN & SLACK_APP_TOKEN"
print_info "  - DISCORD_BOT_TOKEN"
print_info "  - GOOGLE_AI_API_KEY"
print_info "  - OPENAI_API_KEY"
print_info "  - ELEVENLABS_API_KEY (optional)"

# =============================================================================
# PostgreSQL Setup
# =============================================================================

print_header "PostgreSQL Setup"

# Check if PostgreSQL is running
if pg_isready &> /dev/null; then
    print_success "PostgreSQL is running"
else
    print_warning "PostgreSQL is not running"
    print_info "Starting PostgreSQL..."
    brew services start postgresql@15
    sleep 3
    if pg_isready &> /dev/null; then
        print_success "PostgreSQL started"
    else
        print_error "Failed to start PostgreSQL"
        exit 1
    fi
fi

# Create production database
print_info "Creating production database..."
if createdb hal_prod 2>/dev/null; then
    print_success "Created database: hal_prod"
else
    print_warning "Database hal_prod may already exist"
fi

# Enable pgvector extension
print_info "Enabling pgvector extension..."
psql hal_prod -c "CREATE EXTENSION IF NOT EXISTS vector;" &> /dev/null || {
    print_warning "Could not enable pgvector. Install with: brew install pgvector"
}

# =============================================================================
# Elixir Dependencies
# =============================================================================

print_header "Installing Elixir Dependencies"

cd "$PROJECT_ROOT"

print_info "Fetching dependencies..."
mix deps.get

print_info "Compiling dependencies..."
mix deps.compile

print_success "Dependencies installed"

# =============================================================================
# Database Migrations
# =============================================================================

print_header "Running Database Migrations"

print_info "Running migrations..."
MIX_ENV=prod mix ecto.create
MIX_ENV=prod mix ecto.migrate

print_success "Database migrations complete"

# =============================================================================
# Building Release
# =============================================================================

print_header "Building Production Release"

print_info "Compiling assets..."
MIX_ENV=prod mix assets.deploy 2>/dev/null || print_warning "No assets to compile"

print_info "Building release..."
MIX_ENV=prod mix release

print_success "Release built successfully"

# =============================================================================
# launchd Setup (macOS)
# =============================================================================

print_header "Setting Up Auto-Start (launchd)"

PLIST_FILE="$HOME/Library/LaunchAgents/com.hal.assistant.plist"
PLIST_TEMPLATE="$PROJECT_ROOT/com.hal.assistant.plist"

if [ -f "$PLIST_TEMPLATE" ]; then
    print_info "Installing launchd plist..."

    # Replace placeholder paths in plist
    sed "s@\$HOME@$HOME@g" "$PLIST_TEMPLATE" > "$PLIST_FILE"
    sed -i.bak "s@\$PROJECT_ROOT@$PROJECT_ROOT@g" "$PLIST_FILE"
    rm "$PLIST_FILE.bak"

    print_success "Installed launchd plist"

    print_info "Loading launchd service..."
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    launchctl load "$PLIST_FILE"

    print_success "HAL will now start automatically on login"
else
    print_warning "launchd plist template not found"
    print_info "Skipping auto-start setup"
fi

# =============================================================================
# Final Instructions
# =============================================================================

print_header "Setup Complete!"

echo ""
print_success "HAL Assistant is now installed!"
echo ""
print_info "Next steps:"
echo ""
echo "  1. Edit your environment file:"
echo "     nano ~/.hal.env"
echo ""
echo "  2. Add your API tokens (Telegram, Slack, Discord, etc.)"
echo ""
echo "  3. Start HAL manually:"
echo "     ./scripts/deploy.sh"
echo ""
echo "  4. Check HAL status:"
echo "     ./scripts/health_check.sh"
echo ""
echo "  5. View logs:"
echo "     tail -f ~/.hal/logs/hal.log"
echo ""
print_info "HAL will auto-start on next login (via launchd)"
echo ""
print_warning "For production deployment, review config/prod.exs"
echo ""
