#!/usr/bin/env bash
# Fetch recent GitHub activity for a given repository.
# Usage: ./fetch_github.sh [owner/repo] [--hours 24]
# Dependencies: curl, jq
# Respects GITHUB_TOKEN env var for authentication.

set -euo pipefail

REPO="${1:-openclaw/openclaw}"
shift 2>/dev/null || true

HOURS=24
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours) HOURS="$2"; shift 2 ;;
    *)       shift ;;
  esac
done

# Compute since timestamp
if date -v-1d +%s >/dev/null 2>&1; then
  SINCE=$(date -u -v-${HOURS}H +%Y-%m-%dT%H:%M:%SZ)
else
  SINCE=$(date -u -d "${HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ)
fi

OWNER="${REPO%%/*}"
REPONAME="${REPO##*/}"
API="https://api.github.com"

# Build auth header
AUTH_HEADER=""
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
fi

gh_fetch() {
  local endpoint="$1"
  if [[ -n "$AUTH_HEADER" ]]; then
    curl -sL --max-time 15 \
      -H "Accept: application/vnd.github.v3+json" \
      -H "User-Agent: ai-agent-daily-digest" \
      -H "$AUTH_HEADER" \
      "${API}${endpoint}"
  else
    curl -sL --max-time 15 \
      -H "Accept: application/vnd.github.v3+json" \
      -H "User-Agent: ai-agent-daily-digest" \
      "${API}${endpoint}"
  fi
}

# Check if jq is available
if ! command -v jq &>/dev/null; then
  echo '{"error": "jq is required but not installed. Install with: brew install jq (macOS) or apt install jq (Linux)"}' >&2
  exit 1
fi

# Fetch commits
COMMITS=$(gh_fetch "/repos/${OWNER}/${REPONAME}/commits?since=${SINCE}&per_page=30" 2>/dev/null) || COMMITS='{"error":"fetch failed"}'
if echo "$COMMITS" | jq -e '.message' >/dev/null 2>&1; then
  # API error (e.g., 404)
  COMMITS_OUT=$(echo "$COMMITS" | jq -c '{error: .message}')
else
  COMMITS_OUT=$(echo "$COMMITS" | jq -c '[.[] | {sha: .sha[0:7], message: (.commit.message | split("\n")[0]), author: .commit.author.name, date: .commit.author.date}]' 2>/dev/null) || COMMITS_OUT='{"error":"parse failed"}'
fi

# Fetch pull requests
PULLS=$(gh_fetch "/repos/${OWNER}/${REPONAME}/pulls?state=all&sort=updated&direction=desc&per_page=10" 2>/dev/null) || PULLS='{"error":"fetch failed"}'
if echo "$PULLS" | jq -e '.message' >/dev/null 2>&1; then
  PULLS_OUT=$(echo "$PULLS" | jq -c '{error: .message}')
else
  PULLS_OUT=$(echo "$PULLS" | jq -c '[.[] | {number: .number, title: .title, state: .state, author: .user.login, updated: .updated_at}]' 2>/dev/null) || PULLS_OUT='{"error":"parse failed"}'
fi

# Fetch releases
RELEASES=$(gh_fetch "/repos/${OWNER}/${REPONAME}/releases?per_page=3" 2>/dev/null) || RELEASES='{"error":"fetch failed"}'
if echo "$RELEASES" | jq -e '.message' >/dev/null 2>&1; then
  RELEASES_OUT=$(echo "$RELEASES" | jq -c '{error: .message}')
else
  RELEASES_OUT=$(echo "$RELEASES" | jq -c '[.[] | {tag: .tag_name, name: .name, date: .published_at, body: (.body // "")[0:300]}]' 2>/dev/null) || RELEASES_OUT='{"error":"parse failed"}'
fi

# Output combined JSON
jq -n \
  --arg repo "$REPO" \
  --arg since "$SINCE" \
  --argjson commits "$COMMITS_OUT" \
  --argjson pulls "$PULLS_OUT" \
  --argjson releases "$RELEASES_OUT" \
  '{repo: $repo, since: $since, commits: $commits, pull_requests: $pulls, releases: $releases}'
