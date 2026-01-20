#!/bin/bash
# ============================================================
# BugBot Dashboard - Dashboard Generator
# ============================================================
# Generates an interactive HTML dashboard from collected data.
#
# Usage: ./scripts/generate-dashboard.sh
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration if available
[ -f "$PROJECT_DIR/config.env" ] && source "$PROJECT_DIR/config.env"

CSV="$PROJECT_DIR/data/bugbot_results.csv"
DETAILED_FILE="$PROJECT_DIR/data/bugbot_detailed.jsonl"
REPORTS_DIR="$PROJECT_DIR/reports"
mkdir -p "$REPORTS_DIR"

# Check if data exists
if [ ! -f "$CSV" ]; then
    echo "❌ Error: No data file found at $CSV"
    echo ""
    echo "Please run the data fetcher first:"
    echo "  ./scripts/fetch-bugbot-data.sh"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HTML_FILE="$REPORTS_DIR/dashboard_$TIMESTAMP.html"

echo "📊 Generating BugBot Dashboard..."

# ============================================================
# Calculate Statistics
# ============================================================

total_prs=$(tail -n +2 "$CSV" | wc -l | tr -d ' ')
total_issues=$(tail -n +2 "$CSV" | awk -F',' '{sum += $10} END {print sum+0}')
total_high=$(tail -n +2 "$CSV" | awk -F',' '{sum += $7} END {print sum+0}')
total_medium=$(tail -n +2 "$CSV" | awk -F',' '{sum += $8} END {print sum+0}')
total_low=$(tail -n +2 "$CSV" | awk -F',' '{sum += $9} END {print sum+0}')
unique_repos=$(tail -n +2 "$CSV" | cut -d',' -f1 | sed 's/"//g' | sort -u | wc -l | tr -d ' ')
unique_devs=$(tail -n +2 "$CSV" | cut -d',' -f5 | sed 's/"//g' | sort -u | wc -l | tr -d ' ')

# Get date range from data
first_date=$(tail -n +2 "$CSV" | cut -d',' -f6 | sed 's/"//g' | sort | head -1 | cut -d'T' -f1)
last_date=$(tail -n +2 "$CSV" | cut -d',' -f6 | sed 's/"//g' | sort | tail -1 | cut -d'T' -f1)

echo "   📈 PRs: $total_prs"
echo "   🐛 Issues: $total_issues"
echo "   📁 Repos: $unique_repos"
echo "   👥 Developers: $unique_devs"

# ============================================================
# Calculate Weekly Trends
# ============================================================

echo "📈 Calculating weekly trends..."
weekly_data=$(tail -n +2 "$CSV" | awk -F',' '{
    gsub(/"/, "", $6)
    split($6, d, "T")
    week = d[1]
    gsub(/-[0-9][0-9]$/, "", week)
    if (week ~ /^[0-9]{4}-[0-9]{2}$/) {
        weeks[week] += $10
    }
} END {
    for (w in weeks) if (weeks[w] > 0) print w "|" weeks[w]
}' | sort | tail -16)

trend_labels=""
trend_values=""
while IFS='|' read -r week count; do
    [ -z "$week" ] && continue
    [[ ! "$week" =~ ^[0-9]{4}-[0-9]{2}$ ]] && continue
    year=$(echo "$week" | cut -d'-' -f1)
    month=$(echo "$week" | cut -d'-' -f2)
    trend_labels+="'$month-$year',"
    trend_values+="$count,"
done <<< "$weekly_data"

# ============================================================
# Calculate Top Repositories
# ============================================================

repo_data=$(tail -n +2 "$CSV" | awk -F',' '{
    gsub(/"/, "", $1); sum[$1] += $10
} END { for (repo in sum) print sum[repo] "|" repo }' | sort -t'|' -k1 -rn | head -10)

repo_labels=""
repo_values=""
while IFS='|' read -r count repo; do
    repo_labels+="'$repo',"
    repo_values+="$count,"
done <<< "$repo_data"

# ============================================================
# Calculate Top Developers
# ============================================================

dev_data=$(tail -n +2 "$CSV" | awk -F',' '{
    gsub(/"/, "", $5); sum[$5] += $10
} END { for (dev in sum) print sum[dev] "|" dev }' | sort -t'|' -k1 -rn | head -10)

dev_labels=""
dev_values=""
while IFS='|' read -r count dev; do
    dev_labels+="'$dev',"
    dev_values+="$count,"
done <<< "$dev_data"

# ============================================================
# Generate HTML Dashboard
# ============================================================

cat > "$HTML_FILE" << 'HTML_START'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BugBot Analysis Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-datalabels@2"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; padding: 2rem; }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { font-size: 2.5rem; margin-bottom: 0.5rem; color: #f8fafc; }
        .subtitle { color: #94a3b8; margin-bottom: 2rem; font-size: 1.1rem; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
        .stat-card { background: linear-gradient(135deg, #1e293b 0%, #334155 100%); padding: 1.5rem; border-radius: 1rem; text-align: center; border: 1px solid #475569; }
        .stat-value { font-size: 2.5rem; font-weight: bold; background: linear-gradient(90deg, #8b5cf6, #06b6d4); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .stat-label { color: #94a3b8; margin-top: 0.5rem; }
        .charts-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(500px, 1fr)); gap: 1.5rem; margin-bottom: 2rem; }
        .card { background: #1e293b; padding: 1.5rem; border-radius: 1rem; border: 1px solid #334155; }
        .card h3 { margin-bottom: 1rem; color: #f8fafc; }
        .chart-container { height: 300px; position: relative; }
        .severity-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1rem; margin-bottom: 2rem; }
        .severity-card { padding: 1.5rem; border-radius: 1rem; text-align: center; }
        .severity-high { background: linear-gradient(135deg, #7f1d1d 0%, #dc2626 100%); }
        .severity-medium { background: linear-gradient(135deg, #78350f 0%, #f59e0b 100%); }
        .severity-low { background: linear-gradient(135deg, #14532d 0%, #22c55e 100%); }
        .severity-value { font-size: 2rem; font-weight: bold; }
        .severity-label { opacity: 0.9; }
        table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
        th, td { padding: 0.75rem; text-align: left; border-bottom: 1px solid #334155; }
        th { color: #94a3b8; font-weight: 600; }
        tr:hover { background: #334155; }
        .issue-count { background: #8b5cf6; color: white; padding: 0.25rem 0.75rem; border-radius: 9999px; font-size: 0.875rem; }
        .patterns-list { display: flex; flex-direction: column; gap: 0.75rem; }
        .pattern-card { background: linear-gradient(135deg, #1e293b 0%, #334155 100%); padding: 1.25rem; border-radius: 0.75rem; border: 1px solid #475569; cursor: pointer; display: flex; justify-content: space-between; align-items: center; transition: all 0.2s; }
        .pattern-card:hover { transform: translateY(-2px); border-color: #8b5cf6; box-shadow: 0 4px 12px rgba(139,92,246,0.2); }
        .pattern-name { font-weight: 500; }
        .pattern-count { background: #334155; padding: 0.25rem 0.75rem; border-radius: 9999px; font-size: 0.875rem; margin-right: 0.5rem; }
        .pattern-arrow { color: #8b5cf6; }
        .modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.8); display: none; justify-content: center; align-items: center; z-index: 1000; padding: 2rem; }
        .modal-overlay.active { display: flex; }
        .modal { background: #1e293b; border-radius: 1rem; max-width: 700px; width: 100%; max-height: 80vh; overflow-y: auto; border: 1px solid #475569; }
        .modal-header { padding: 1.5rem; border-bottom: 1px solid #334155; display: flex; justify-content: space-between; align-items: center; }
        .modal-title { font-size: 1.25rem; font-weight: 600; }
        .modal-close { background: none; border: none; color: #94a3b8; font-size: 1.5rem; cursor: pointer; }
        .modal-close:hover { color: #f8fafc; }
        .modal-body { padding: 1.5rem; }
        .example-item { background: #0f172a; border-left: 3px solid #8b5cf6; padding: 1rem; margin-bottom: 1rem; border-radius: 0 0.5rem 0.5rem 0; }
        .example-repo { color: #8b5cf6; font-weight: 500; margin-bottom: 0.25rem; }
        .example-title { color: #e2e8f0; margin-bottom: 0.25rem; }
        .example-dev { color: #94a3b8; font-size: 0.875rem; }
        .example-link { color: #06b6d4; text-decoration: none; font-size: 0.875rem; }
        .example-link:hover { text-decoration: underline; }
        .dev-select { width: 100%; padding: 0.75rem 1rem; font-size: 1rem; background: #0f172a; color: #e2e8f0; border: 1px solid #475569; border-radius: 0.5rem; cursor: pointer; appearance: none; background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='%2394a3b8' viewBox='0 0 16 16'%3E%3Cpath d='M8 11L3 6h10l-5 5z'/%3E%3C/svg%3E"); background-repeat: no-repeat; background-position: right 1rem center; }
        .dev-select:hover { border-color: #8b5cf6; }
        .dev-select:focus { outline: none; border-color: #8b5cf6; box-shadow: 0 0 0 2px rgba(139,92,246,0.2); }
        .dev-select option { background: #1e293b; color: #e2e8f0; }
        @media (max-width: 768px) {
            .charts-grid { grid-template-columns: 1fr; }
            .severity-grid { grid-template-columns: 1fr; }
            h1 { font-size: 1.75rem; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🐛 BugBot Analysis Dashboard</h1>
HTML_START

# Add subtitle with date range
cat >> "$HTML_FILE" << HTML_SUBTITLE
        <p class="subtitle">$first_date to $last_date | $unique_repos repositories | $unique_devs developers</p>
HTML_SUBTITLE

# Add stats cards
cat >> "$HTML_FILE" << HTML_STATS
        <div class="stats-grid" style="grid-template-columns: repeat(4, 1fr);">
            <div class="stat-card">
                <div class="stat-value">$total_prs</div>
                <div class="stat-label">PRs Reviewed</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$total_issues</div>
                <div class="stat-label">Issues Found</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$unique_repos</div>
                <div class="stat-label">Repositories</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$unique_devs</div>
                <div class="stat-label">Developers</div>
            </div>
        </div>

        <div class="severity-grid">
            <div class="severity-card severity-high">
                <div class="severity-value">$total_high</div>
                <div class="severity-label">🔴 High Severity</div>
            </div>
            <div class="severity-card severity-medium">
                <div class="severity-value">$total_medium</div>
                <div class="severity-label">🟡 Medium Severity</div>
            </div>
            <div class="severity-card severity-low">
                <div class="severity-value">$total_low</div>
                <div class="severity-label">🟢 Low Severity</div>
            </div>
        </div>

        <div class="charts-grid">
            <div class="card">
                <h3>📈 Issues Trend (Monthly)</h3>
                <div class="chart-container">
                    <canvas id="trendChart"></canvas>
                </div>
            </div>
            <div class="card">
                <h3>🎯 Severity Distribution</h3>
                <div class="chart-container">
                    <canvas id="severityChart"></canvas>
                </div>
            </div>
        </div>

        <div class="charts-grid">
            <div class="card">
                <h3>📁 Top Repositories</h3>
                <table>
                    <thead><tr><th>Repository</th><th>Issues</th></tr></thead>
                    <tbody>
HTML_STATS

# Add top repos table
tail -n +2 "$CSV" | awk -F',' '{
    gsub(/"/, "", $1); sum[$1] += $10
} END { for (repo in sum) print sum[repo] "|" repo }' | sort -t'|' -k1 -rn | head -10 | while IFS='|' read -r count repo; do
    echo "                        <tr><td>$repo</td><td><span class=\"issue-count\">$count</span></td></tr>" >> "$HTML_FILE"
done

cat >> "$HTML_FILE" << 'HTML_REPOS_END'
                    </tbody>
                </table>
            </div>
            <div class="card">
                <h3>👥 Top Developers</h3>
                <table>
                    <thead><tr><th>Developer</th><th>Issues</th></tr></thead>
                    <tbody>
HTML_REPOS_END

# Add top developers table
tail -n +2 "$CSV" | awk -F',' '{
    gsub(/"/, "", $5); sum[$5] += $10
} END { for (dev in sum) print sum[dev] "|" dev }' | sort -t'|' -k1 -rn | head -10 | while IFS='|' read -r count dev; do
    echo "                        <tr><td>$dev</td><td><span class=\"issue-count\">$count</span></td></tr>" >> "$HTML_FILE"
done

cat >> "$HTML_FILE" << 'HTML_DEVS_END'
                    </tbody>
                </table>
            </div>
        </div>

        <div class="card" style="margin-bottom: 2rem;">
            <h3>👤 Developer Issues Lookup</h3>
            <p style="color: #94a3b8; margin-bottom: 1rem;">Select a developer to see their recent issues:</p>
            <select id="developerSelect" class="dev-select" onchange="showDeveloperIssues()">
                <option value="">-- Select Developer --</option>
HTML_DEVS_END

# Add all developers to dropdown
tail -n +2 "$CSV" | awk -F',' '{
    gsub(/"/, "", $5); devs[$5]++
} END { for (dev in devs) print dev }' | sort -f | while read -r dev; do
    [ -z "$dev" ] && continue
    [[ "$dev" =~ ^[0-9]+$ ]] && continue
    [[ ${#dev} -lt 2 ]] && continue
    count=$(tail -n +2 "$CSV" | awk -F',' -v d="$dev" 'BEGIN{c=0} {gsub(/"/, "", $5); if($5==d) c+=$10} END{print c}')
    echo "                <option value=\"$dev\">$dev ($count issues)</option>" >> "$HTML_FILE"
done

cat >> "$HTML_FILE" << 'HTML_SELECT_END'
            </select>
            <div id="developerIssuesContainer" style="margin-top: 1.5rem; max-height: 400px; overflow-y: auto;"></div>
        </div>
    </div>
HTML_SELECT_END

# Generate developer issues data as JSON
echo "    <script>" >> "$HTML_FILE"
echo "        const developerIssues = {" >> "$HTML_FILE"

tail -n +2 "$CSV" | awk -F',' '{
    gsub(/"/, "", $5); devs[$5]++
} END { for (dev in devs) print dev }' | sort -f | while read -r dev; do
    [ -z "$dev" ] && continue
    [[ "$dev" =~ ^[0-9]+$ ]] && continue
    [[ ${#dev} -lt 2 ]] && continue
    echo "            \"$dev\": [" >> "$HTML_FILE"
    
    awk -F',' -v d="$dev" '
    NR > 1 {
        gsub(/"/, "", $5)
        if ($5 == d) {
            repo = $1; gsub(/"/, "", repo)
            title = $3; gsub(/"/, "", title); gsub(/'\''/, "", title)
            title = substr(title, 1, 80)
            url = $4; gsub(/"/, "", url)
            date = $6; gsub(/"/, "", date)
            date = substr(date, 1, 10)
            issues = $10; gsub(/[^0-9]/, "", issues)
            if (issues == "") issues = 0
            if (url ~ /^https:\/\/github\.com/) {
                print date "|" repo "|" title "|" url "|" issues
            }
        }
    }' "$CSV" | sort -r | head -15 | while IFS='|' read -r date repo title url issues; do
        title=$(echo "$title" | sed "s/'/\\\\'/g" | sed 's/"/\\"/g')
        echo "                {repo: '$repo', title: '$title', url: '$url', date: '$date', issues: $issues}," >> "$HTML_FILE"
    done
    
    echo "            ]," >> "$HTML_FILE"
done

echo "        };" >> "$HTML_FILE"

# Add JavaScript functions
cat >> "$HTML_FILE" << 'HTML_DEV_SCRIPT'

        function showDeveloperIssues() {
            const select = document.getElementById('developerSelect');
            const container = document.getElementById('developerIssuesContainer');
            const dev = select.value;
            
            if (!dev) {
                container.innerHTML = '';
                return;
            }
            
            const issues = developerIssues[dev] || [];
            
            if (issues.length === 0) {
                container.innerHTML = '<p style="color: #94a3b8;">No issues found for this developer.</p>';
                return;
            }
            
            const totalIssues = issues.reduce((sum, i) => sum + (i.issues || 0), 0);
            let html = '<div style="font-size: 0.9rem; color: #94a3b8; margin-bottom: 0.5rem;">' + issues.length + ' PRs with ' + totalIssues + ' issues:</div>';
            
            issues.forEach(issue => {
                html += '<div class="example-item" style="margin-bottom: 0.75rem;">' +
                    '<div class="example-repo">' + issue.repo + ' <span style="color:#64748b;font-size:0.8rem;">(' + issue.date + ')</span> <span class="pattern-count" style="font-size:0.75rem;">' + issue.issues + ' issues</span></div>' +
                    '<div class="example-title">' + issue.title + '</div>' +
                    '<a href="' + issue.url + '" target="_blank" class="example-link">View PR →</a>' +
                    '</div>';
            });
            
            container.innerHTML = html;
        }
    </script>
HTML_DEV_SCRIPT

# Add chart scripts
cat >> "$HTML_FILE" << HTML_CHARTS
    <script>
        // Register Chart.js plugins
        Chart.register(ChartDataLabels);
        
        // Trend Chart
        new Chart(document.getElementById('trendChart'), {
            type: 'bar',
            data: {
                labels: [$trend_labels],
                datasets: [{
                    label: 'Issues',
                    data: [$trend_values],
                    backgroundColor: '#8b5cf6',
                    borderColor: '#a78bfa',
                    borderWidth: 1,
                    borderRadius: 4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    datalabels: {
                        anchor: 'end',
                        align: 'top',
                        color: '#e2e8f0',
                        font: { weight: 'bold', size: 12 },
                        formatter: (value) => value.toLocaleString()
                    }
                },
                scales: {
                    x: { grid: { display: false }, ticks: { color: '#94a3b8' } },
                    y: { grid: { color: '#334155' }, ticks: { color: '#94a3b8' }, beginAtZero: true }
                }
            }
        });

        // Severity Chart
        new Chart(document.getElementById('severityChart'), {
            type: 'doughnut',
            data: {
                labels: ['High', 'Medium', 'Low'],
                datasets: [{
                    data: [$total_high, $total_medium, $total_low],
                    backgroundColor: ['#dc2626', '#f59e0b', '#22c55e']
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'right',
                        labels: { color: '#e2e8f0', padding: 20 }
                    },
                    datalabels: {
                        display: true,
                        color: '#ffffff',
                        font: { weight: 'bold', size: 14 },
                        formatter: (value) => value.toLocaleString()
                    }
                }
            }
        });
    </script>
</body>
</html>
HTML_CHARTS

echo ""
echo "✅ Dashboard generated: $HTML_FILE"
echo ""

# Try to open the dashboard
if [[ "$OSTYPE" == "darwin"* ]]; then
    open "$HTML_FILE" 2>/dev/null && echo "🌐 Dashboard opened in browser!"
elif command -v xdg-open &>/dev/null; then
    xdg-open "$HTML_FILE" 2>/dev/null && echo "🌐 Dashboard opened in browser!"
else
    echo "📄 Open $HTML_FILE in your browser to view the dashboard"
fi
