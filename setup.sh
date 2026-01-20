#!/bin/bash
# ============================================================
# BugBot Dashboard - Setup Script
# ============================================================
# Quick setup wizard for the BugBot Dashboard
#
# Usage: ./setup.sh
# ============================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🐛 BugBot Dashboard Setup"
echo "========================="
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check for GitHub CLI
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed."
    echo ""
    echo "Please install it:"
    echo "  - macOS: brew install gh"
    echo "  - Linux: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
    echo "  - Windows: https://github.com/cli/cli/releases"
    exit 1
fi
echo "   ✅ GitHub CLI installed"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "❌ jq is not installed."
    echo ""
    echo "Please install it:"
    echo "  - macOS: brew install jq"
    echo "  - Linux: sudo apt install jq (Debian/Ubuntu) or sudo yum install jq (RHEL/CentOS)"
    echo "  - Windows: choco install jq"
    exit 1
fi
echo "   ✅ jq installed"

# Check GitHub CLI authentication
if ! gh auth status &>/dev/null; then
    echo ""
    echo "⚠️  GitHub CLI is not authenticated."
    echo ""
    read -p "Would you like to authenticate now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        gh auth login
    else
        echo "Please run 'gh auth login' before using this tool."
        exit 1
    fi
fi
echo "   ✅ GitHub CLI authenticated"

echo ""
echo "All prerequisites met! ✅"
echo ""

# Setup configuration
if [ -f "$PROJECT_DIR/config.env" ]; then
    echo "📄 Configuration file found (config.env)"
    read -p "Would you like to reconfigure? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Setup complete! You can now run:"
        echo "  ./scripts/fetch-bugbot-data.sh   # Fetch data from GitHub"
        echo "  ./scripts/generate-dashboard.sh  # Generate dashboard"
        exit 0
    fi
fi

echo ""
echo "📝 Configuration Setup"
echo "----------------------"
echo ""

# Get GitHub token
echo "You need a GitHub Personal Access Token with 'repo' and 'read:org' scopes."
echo "Create one at: https://github.com/settings/tokens"
echo ""
read -p "Enter your GitHub Token (or press Enter to use gh CLI token): " github_token

if [ -z "$github_token" ]; then
    github_token=$(gh auth token 2>/dev/null || echo "")
    if [ -z "$github_token" ]; then
        echo "❌ Could not get token from gh CLI. Please provide a token manually."
        exit 1
    fi
    echo "   ✅ Using token from GitHub CLI"
fi

# Get organization
echo ""
read -p "Enter your GitHub Organization name: " org_name

if [ -z "$org_name" ]; then
    echo "❌ Organization name is required."
    exit 1
fi

# Get date range
echo ""
echo "📅 Date Range Configuration"
echo "   Leave empty for defaults (last 3 months)"
echo ""

read -p "Start date (YYYY-MM-DD) [3 months ago]: " start_date
read -p "End date (YYYY-MM-DD) [today]: " end_date

# Get bot username
echo ""
read -p "Code review bot username [cursor[bot]]: " bot_user
bot_user="${bot_user:-cursor[bot]}"

# Create config file
cat > "$PROJECT_DIR/config.env" << EOF
# BugBot Dashboard Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# GitHub Configuration
export GITHUB_TOKEN="$github_token"
export ORG="$org_name"

# Date Range
export START_DATE="${start_date}"
export END_DATE="${end_date}"

# Bot Configuration
export BUGBOT_USER="$bot_user"

# Performance Settings
export API_DELAY_MS=100
export MAX_RETRIES=3
EOF

echo ""
echo "✅ Configuration saved to config.env"
echo ""

# Make scripts executable
chmod +x "$PROJECT_DIR/scripts/"*.sh

echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Fetch data:     ./scripts/fetch-bugbot-data.sh"
echo "  2. View dashboard: ./scripts/generate-dashboard.sh"
echo ""
echo "Or try with sample data:"
echo "  cp data/sample_bugbot_results.csv data/bugbot_results.csv"
echo "  ./scripts/generate-dashboard.sh"
