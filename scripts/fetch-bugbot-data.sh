#!/bin/bash
# ============================================================
# BugBot Dashboard - Data Fetcher
# ============================================================
# Fetches all code review bot comments from GitHub PRs
# and extracts issues with severity levels.
#
# Usage: ./scripts/fetch-bugbot-data.sh
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
if [ ! -f "$PROJECT_DIR/config.env" ]; then
    echo "❌ Error: config.env not found!"
    echo ""
    echo "Please create config.env from the template:"
    echo "  cp config.env.example config.env"
    echo "  # Edit config.env with your GitHub token and organization"
    exit 1
fi

source "$PROJECT_DIR/config.env"

# Validate required configuration
if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "your_github_token_here" ]; then
    echo "❌ Error: GITHUB_TOKEN is not configured!"
    echo "Please set your GitHub token in config.env"
    exit 1
fi

if [ -z "$ORG" ] || [ "$ORG" = "your-org-name" ]; then
    echo "❌ Error: ORG (organization) is not configured!"
    echo "Please set your GitHub organization in config.env"
    exit 1
fi

# Set defaults for optional configs
export BUGBOT_USER="${BUGBOT_USER:-cursor[bot]}"
export API_DELAY_MS="${API_DELAY_MS:-100}"
export MAX_RETRIES="${MAX_RETRIES:-3}"
export END_DATE="${END_DATE:-$(date +%Y-%m-%d)}"

# Calculate default start date (3 months ago) if not set
if [ -z "$START_DATE" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        START_DATE=$(date -v-3m +%Y-%m-%d)
    else
        START_DATE=$(date -d "3 months ago" +%Y-%m-%d)
    fi
fi

export GH_TOKEN="$GITHUB_TOKEN"

DATA_DIR="$PROJECT_DIR/data"
RESULTS_FILE="$DATA_DIR/bugbot_results.csv"
DETAILED_FILE="$DATA_DIR/bugbot_detailed.jsonl"
CHECKPOINT_FILE="$DATA_DIR/fetch_checkpoint.txt"
LOG_FILE="$DATA_DIR/fetch.log"

mkdir -p "$DATA_DIR"

# Logging function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# Rate limit handler
wait_for_rate_limit() {
    local resource="${1:-core}"
    local min_required="${2:-50}"
    
    while true; do
        local remaining
        remaining=$(gh api rate_limit 2>/dev/null | jq ".resources.$resource.remaining" || echo "0")
        
        if [ "$remaining" -ge "$min_required" ]; then
            return
        fi
        
        local reset
        reset=$(gh api rate_limit 2>/dev/null | jq ".resources.$resource.reset" || echo "0")
        local now
        now=$(date +%s)
        local wait_time=$((reset - now + 5))
        
        if [ "$wait_time" -gt 0 ] && [ "$wait_time" -lt 3700 ]; then
            log "⏳ Rate limit ($resource): $remaining remaining. Waiting $wait_time seconds..."
            sleep $wait_time
        else
            sleep 60
        fi
    done
}

# Generate weekly date ranges for chunked fetching
generate_date_ranges() {
    local start_date="$1"
    local end_date="$2"
    
    local current="$start_date"
    while [[ "$current" < "$end_date" ]]; do
        local next
        if [[ "$OSTYPE" == "darwin"* ]]; then
            next=$(date -j -v+7d -f "%Y-%m-%d" "$current" "+%Y-%m-%d" 2>/dev/null)
        else
            next=$(date -d "$current + 7 days" "+%Y-%m-%d")
        fi
        
        if [[ "$next" > "$end_date" ]]; then
            next="$end_date"
        fi
        echo "$current..$next"
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            current=$(date -j -v+1d -f "%Y-%m-%d" "$next" "+%Y-%m-%d" 2>/dev/null)
        else
            current=$(date -d "$next + 1 day" "+%Y-%m-%d")
        fi
    done
}

# Count issues in bot comments (looks for ### headings)
count_issues_in_comments() {
    local comments_json="$1"
    
    local bodies
    bodies=$(echo "$comments_json" | jq -r ".[] | select(.user.login == \"$BUGBOT_USER\") | .body" 2>/dev/null)
    
    if [ -z "$bodies" ]; then
        echo "0"
        return
    fi
    
    local count
    count=$(echo "$bodies" | grep -c "^### " 2>/dev/null || echo "0")
    echo "$count" | tr -d ' \n'
}

# Extract severity counts from bot comments
get_severity_counts() {
    local comments_json="$1"
    
    local bodies
    bodies=$(echo "$comments_json" | jq -r ".[] | select(.user.login == \"$BUGBOT_USER\") | .body" 2>/dev/null)
    
    if [ -z "$bodies" ]; then
        echo "0,0,0"
        return
    fi
    
    local high medium low
    high=$(echo "$bodies" | grep -ic "High Severity" 2>/dev/null || echo "0")
    medium=$(echo "$bodies" | grep -ic "Medium Severity" 2>/dev/null || echo "0")
    low=$(echo "$bodies" | grep -ic "Low Severity" 2>/dev/null || echo "0")
    
    echo "$(echo $high | tr -d ' \n'),$(echo $medium | tr -d ' \n'),$(echo $low | tr -d ' \n')"
}

# ============================================================
# Main Execution
# ============================================================

log "=============================================="
log "🐛 BugBot Dashboard - Data Fetcher"
log "=============================================="
log "📍 Organization: $ORG"
log "🤖 Bot User: $BUGBOT_USER"
log "📅 Date range: $START_DATE to $END_DATE"
log "=============================================="

# Check GitHub CLI authentication
if ! gh auth status &>/dev/null; then
    log "❌ Error: GitHub CLI is not authenticated!"
    log "Please run: gh auth login"
    exit 1
fi

# Initialize or resume from checkpoint
if [ -f "$CHECKPOINT_FILE" ]; then
    last_completed=$(cat "$CHECKPOINT_FILE")
    log "📥 Resuming from checkpoint: $last_completed"
else
    # Initialize CSV with headers
    echo "repository,pr_number,pr_title,pr_url,pr_author,pr_date,high_severity,medium_severity,low_severity,total_issues" > "$RESULTS_FILE"
    > "$DETAILED_FILE"
    last_completed=""
fi

# Generate date ranges
date_ranges=$(generate_date_ranges "$START_DATE" "$END_DATE")

skip_mode=true
if [ -z "$last_completed" ]; then
    skip_mode=false
fi

total_prs=0
total_issues=0

for range in $date_ranges; do
    # Skip already processed ranges
    if [ "$skip_mode" = true ]; then
        if [ "$range" = "$last_completed" ]; then
            skip_mode=false
        fi
        continue
    fi
    
    log "📆 Processing: $range"
    
    # Wait for rate limits
    wait_for_rate_limit "search" 2
    wait_for_rate_limit "core" 100
    
    # Count PRs in this range
    count_result=$(gh api "search/issues?q=org:$ORG+is:pr+commenter:$BUGBOT_USER+updated:$range&per_page=1" 2>/dev/null || echo '{"total_count":0}')
    range_count=$(echo "$count_result" | jq '.total_count' || echo "0")
    
    log "   Found $range_count PRs"
    
    if [ "$range_count" = "0" ]; then
        echo "$range" > "$CHECKPOINT_FILE"
        continue
    fi
    
    # Fetch all pages (max 10 pages = 1000 results per range)
    page=1
    max_pages=$(( (range_count + 99) / 100 ))
    [ "$max_pages" -gt 10 ] && max_pages=10
    
    while [ $page -le $max_pages ]; do
        wait_for_rate_limit "search" 2
        
        search_result=$(gh api "search/issues?q=org:$ORG+is:pr+commenter:$BUGBOT_USER+updated:$range&per_page=100&page=$page" 2>/dev/null || echo '{"items":[]}')
        
        items_count=$(echo "$search_result" | jq '.items | length')
        
        if [ "$items_count" = "0" ] || [ -z "$items_count" ]; then
            break
        fi
        
        # Process each PR
        while IFS= read -r pr; do
            wait_for_rate_limit "core" 20
            
            pr_number=$(echo "$pr" | jq -r '.number')
            pr_title=$(echo "$pr" | jq -r '.title' | tr ',' ';' | tr '"' "'" | head -c 100)
            pr_url=$(echo "$pr" | jq -r '.html_url')
            pr_author=$(echo "$pr" | jq -r '.user.login')
            pr_date=$(echo "$pr" | jq -r '.updated_at')
            
            # Extract repo name from URL
            repo_name=$(echo "$pr_url" | sed 's|.*/\([^/]*\)/pull/.*|\1|')
            
            # Get PR review comments (inline comments)
            pr_comments=$(gh api "repos/$ORG/$repo_name/pulls/$pr_number/comments?per_page=100" --paginate 2>/dev/null || echo "[]")
            
            if echo "$pr_comments" | jq empty 2>/dev/null; then
                issue_count=$(count_issues_in_comments "$pr_comments")
                
                if [ "$issue_count" -gt 0 ] 2>/dev/null; then
                    severity=$(get_severity_counts "$pr_comments")
                    high=$(echo "$severity" | cut -d',' -f1 | tr -d ' \n')
                    medium=$(echo "$severity" | cut -d',' -f2 | tr -d ' \n')
                    low=$(echo "$severity" | cut -d',' -f3 | tr -d ' \n')
                    issue_count=$(echo "$issue_count" | tr -d ' \n')
                    
                    printf '"%s",%s,"%s","%s","%s","%s",%s,%s,%s,%s\n' \
                        "$repo_name" "$pr_number" "$pr_title" "$pr_url" "$pr_author" "$pr_date" \
                        "$high" "$medium" "$low" "$issue_count" >> "$RESULTS_FILE"
                    
                    # Save detailed data for pattern analysis
                    echo "$pr_comments" | jq -c --arg repo "$repo_name" --arg pr "$pr_number" \
                        '{repo: $repo, pr: ($pr | tonumber), comments: [.[] | select(.user.login == "'"$BUGBOT_USER"'") | {path: .path, body: .body[:500]}]}' >> "$DETAILED_FILE" 2>/dev/null
                    
                    total_prs=$((total_prs + 1))
                    total_issues=$((total_issues + issue_count))
                fi
            fi
            
            sleep 0.05
        done < <(echo "$search_result" | jq -c '.items[]')
        
        page=$((page + 1))
    done
    
    # Save checkpoint
    echo "$range" > "$CHECKPOINT_FILE"
    
    # Progress update
    current_prs=$(tail -n +2 "$RESULTS_FILE" 2>/dev/null | wc -l | tr -d ' ')
    current_issues=$(tail -n +2 "$RESULTS_FILE" 2>/dev/null | awk -F',' '{sum+=$10} END {print sum+0}')
    log "   Progress: $current_prs PRs, $current_issues issues"
done

# Final summary
final_prs=$(tail -n +2 "$RESULTS_FILE" | wc -l | tr -d ' ')
final_issues=$(tail -n +2 "$RESULTS_FILE" | awk -F',' '{sum+=$10} END {print sum+0}')
unique_repos=$(tail -n +2 "$RESULTS_FILE" | cut -d',' -f1 | sed 's/"//g' | sort -u | wc -l | tr -d ' ')
unique_devs=$(tail -n +2 "$RESULTS_FILE" | cut -d',' -f5 | sed 's/"//g' | sort -u | wc -l | tr -d ' ')

total_high=$(tail -n +2 "$RESULTS_FILE" | awk -F',' '{sum+=$7} END {print sum+0}')
total_medium=$(tail -n +2 "$RESULTS_FILE" | awk -F',' '{sum+=$8} END {print sum+0}')
total_low=$(tail -n +2 "$RESULTS_FILE" | awk -F',' '{sum+=$9} END {print sum+0}')

log "=============================================="
log "🎉 Fetch Complete!"
log "=============================================="
log "📊 PRs with issues: $final_prs"
log "🐛 Total issues: $final_issues"
log "   🔴 High: $total_high"
log "   🟡 Medium: $total_medium"
log "   🟢 Low: $total_low"
log "📁 Unique repos: $unique_repos"
log "👥 Unique developers: $unique_devs"
log "=============================================="

# Cleanup checkpoint on successful completion
rm -f "$CHECKPOINT_FILE"

echo ""
echo "✅ Data fetched successfully!"
echo "📄 Results saved to: $RESULTS_FILE"
echo ""
echo "Next step: Run ./scripts/generate-dashboard.sh to create the dashboard"
