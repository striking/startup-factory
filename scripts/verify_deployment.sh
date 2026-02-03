#!/bin/bash
# Quick verification script for deployment configuration

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Verifying HAL deployment configuration..."
echo ""

ERRORS=0

# Check files exist
FILES=(
    ".env.example"
    ".env.production"
    "com.hal.assistant.plist"
    "config/prod.exs"
    "scripts/setup.sh"
    "scripts/deploy.sh"
    "scripts/health_check.sh"
    "scripts/backup.sh"
    "scripts/restore.sh"
    "DEPLOYMENT.md"
)

echo "Checking required files..."
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file"
    else
        echo -e "${RED}✗${NC} $file (missing)"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "Checking scripts are executable..."
for script in scripts/*.sh; do
    if [ -x "$script" ]; then
        echo -e "${GREEN}✓${NC} $script"
    else
        echo -e "${RED}✗${NC} $script (not executable)"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "Checking .env.example has all required vars..."
REQUIRED_VARS=(
    "DATABASE_URL"
    "SECRET_KEY_BASE"
    "PHX_HOST"
    "PORT"
    "TELEGRAM_BOT_TOKEN"
    "SLACK_BOT_TOKEN"
    "GOOGLE_AI_API_KEY"
)

for var in "${REQUIRED_VARS[@]}"; do
    if grep -q "^${var}=" .env.example; then
        echo -e "${GREEN}✓${NC} $var"
    else
        echo -e "${RED}✗${NC} $var (missing from .env.example)"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All deployment configuration checks passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) found${NC}"
    exit 1
fi
