#!/usr/bin/env bash
# Fetch recent AI Agent news from curated RSS feeds.
# Usage: ./fetch_rss.sh [--hours 24] [--json]
# Dependencies: curl, awk (POSIX), sed

set -euo pipefail

HOURS=24
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours) HOURS="$2"; shift 2 ;;
    --json)  JSON_OUTPUT=true; shift ;;
    *)       shift ;;
  esac
done

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# RSS feeds: pipe-separated name|url
FEEDS=(
  "Hacker News - AI Agent|https://hnrss.org/newest?q=AI+agent&count=30"
  "TechCrunch AI|https://techcrunch.com/category/artificial-intelligence/feed/"
  "VentureBeat AI|https://venturebeat.com/feed/"
  "MIT Technology Review|https://www.technologyreview.com/feed/"
  "OpenAI Blog|https://openai.com/blog/rss.xml"
  "Google AI Blog|https://blog.google/technology/ai/rss/"
)

FEED_COUNT=${#FEEDS[@]}
ITEMS_FILE="$TMPDIR_WORK/items.tsv"
ERRORS_FILE="$TMPDIR_WORK/errors.txt"
touch "$ITEMS_FILE" "$ERRORS_FILE"

# Fetch all feeds in parallel
for i in $(seq 0 $((FEED_COUNT - 1))); do
  IFS='|' read -r _name _url <<< "${FEEDS[$i]}"
  (
    curl -sL --max-time 15 \
      -H "User-Agent: ai-agent-daily-digest/1.0" \
      "$_url" > "$TMPDIR_WORK/feed_${i}.xml" 2>/dev/null \
    || echo "" > "$TMPDIR_WORK/feed_${i}.xml"
  ) &
done
wait

# Parse each feed with awk (POSIX compatible - no capture groups)
for i in $(seq 0 $((FEED_COUNT - 1))); do
  IFS='|' read -r feed_name _url <<< "${FEEDS[$i]}"
  feedfile="$TMPDIR_WORK/feed_${i}.xml"

  if [[ ! -s "$feedfile" ]]; then
    echo "$feed_name: fetch failed" >> "$ERRORS_FILE"
    continue
  fi

  # Flatten XML to single line per item, then parse
  # 1. Join all lines into one
  # 2. Split on </item> or </entry>
  # 3. Extract fields with sub/gsub
  tr '\n\r' '  ' < "$feedfile" | \
  sed 's/<\/item>/\n/g; s/<\/entry>/\n/g' | \
  awk -v source="$feed_name" 'BEGIN { OFS="\t" }
  {
    # Extract title
    s = $0
    title = ""
    if (index(s, "<title") > 0) {
      t = s
      sub(/.*<title[^>]*>/, "", t)
      sub(/<\/title>.*/, "", t)
      gsub(/<!\[CDATA\[/, "", t)
      gsub(/\]\]>/, "", t)
      title = t
    }
    if (title == "" || title == s) next

    # Extract link
    link = ""
    if (index(s, "<link") > 0) {
      t = s
      # Try <link>url</link> first
      if (index(t, "</link>") > 0) {
        sub(/.*<link[^>]*>/, "", t)
        sub(/<\/link>.*/, "", t)
        if (t != s) link = t
      }
      # Try href= attribute
      if (link == "" && index(s, "href=") > 0) {
        t = s
        sub(/.*href="/, "", t)
        sub(/".*/, "", t)
        if (t != s) link = t
      }
    }

    # Extract pubDate / updated / published
    pubdate = ""
    if (index(s, "<pubDate>") > 0) {
      t = s; sub(/.*<pubDate>/, "", t); sub(/<\/pubDate>.*/, "", t)
      if (t != s) pubdate = t
    }
    if (pubdate == "" && index(s, "<updated>") > 0) {
      t = s; sub(/.*<updated>/, "", t); sub(/<\/updated>.*/, "", t)
      if (t != s) pubdate = t
    }
    if (pubdate == "" && index(s, "<published>") > 0) {
      t = s; sub(/.*<published>/, "", t); sub(/<\/published>.*/, "", t)
      if (t != s) pubdate = t
    }

    # Extract description / summary
    summary = ""
    if (index(s, "<description") > 0) {
      t = s; sub(/.*<description[^>]*>/, "", t); sub(/<\/description>.*/, "", t)
      if (t != s) summary = t
    }
    if (summary == "" && index(s, "<summary") > 0) {
      t = s; sub(/.*<summary[^>]*>/, "", t); sub(/<\/summary>.*/, "", t)
      if (t != s) summary = t
    }

    # Clean CDATA, HTML tags, entities
    gsub(/<!\[CDATA\[/, "", title); gsub(/\]\]>/, "", title)
    gsub(/<!\[CDATA\[/, "", summary); gsub(/\]\]>/, "", summary)
    gsub(/<[^>]*>/, " ", summary)
    gsub(/&amp;/, "\\&", summary); gsub(/&lt;/, "<", summary); gsub(/&gt;/, ">", summary)
    gsub(/&amp;/, "\\&", title); gsub(/&lt;/, "<", title); gsub(/&gt;/, ">", title)
    gsub(/\t/, " ", title); gsub(/\t/, " ", link)
    gsub(/\t/, " ", pubdate); gsub(/\t/, " ", summary)
    gsub(/  +/, " ", summary); sub(/^ /, "", summary); sub(/ $/, "", summary)
    if (length(summary) > 500) summary = substr(summary, 1, 500)

    if (title != "") print source, title, link, pubdate, summary
  }' >> "$ITEMS_FILE"
done

TOTAL=$(wc -l < "$ITEMS_FILE" | tr -d ' ')

# Filter by time and score relevance
awk -F'\t' -v hours="$HOURS" '
BEGIN {
  OFS = "\t"
  split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m_arr)
  for (i = 1; i <= 12; i++) mon[m_arr[i]] = i

  "date +%s" | getline now; close("date +%s")
  cutoff = now - hours * 3600

  nkw = split("agent agentic autonomous mcp claude gpt gemini copilot langchain openai anthropic", kw_arr)
}

function mkepoch(yr, mo, dy, h, mi, se,    t, y) {
  t = 0
  for (y = 1970; y < yr; y++)
    t += (y%4==0 && (y%100!=0 || y%400==0)) ? 366 : 365
  split("31 28 31 30 31 30 31 31 30 31 30 31", _dm)
  if (yr%4==0 && (yr%100!=0 || yr%400==0)) _dm[2] = 29
  for (_m = 1; _m < mo; _m++) t += _dm[_m]
  t += dy - 1
  return t * 86400 + h * 3600 + mi * 60 + se
}

function parse_date(s,    n2, p, j, d, yr, hms, tz, tzoff, ep, dm2) {
  # RFC 2822: "Mon, 07 Mar 2026 18:32:36 +0000"
  n2 = split(s, p, /[ ,\t]+/)
  for (j = 1; j <= n2; j++) {
    if (p[j] in mon) {
      d = p[j-1]+0; yr = p[j+1]+0
      split(p[j+2], hms, ":"); tz = p[j+3]
      ep = mkepoch(yr, mon[p[j]], d, hms[1]+0, hms[2]+0, hms[3]+0)
      if (tz ~ /^[+-][0-9][0-9][0-9][0-9]$/) {
        tzoff = (substr(tz,1,3)+0)*3600 + (substr(tz,4,2)+0)*60
        ep -= tzoff
      }
      return ep
    }
  }
  # ISO 8601: "2026-03-07T18:32:36+00:00" or "2026-03-07T18:32:36Z"
  if (s ~ /^[0-9][0-9][0-9][0-9]-/) {
    gsub(/Z/, "+0000", s)
    n2 = split(s, p, "T")
    split(p[1], dm2, "-")
    tz = ""
    if (match(p[2], /[+-]/)) {
      tz = substr(p[2], RSTART)
      gsub(/:/, "", tz)
      p[2] = substr(p[2], 1, RSTART-1)
    }
    split(p[2], hms, ":")
    ep = mkepoch(dm2[1]+0, dm2[2]+0, dm2[3]+0, hms[1]+0, hms[2]+0, hms[3]+0)
    if (tz ~ /^[+-][0-9]+/) {
      tzoff = (substr(tz,1,3)+0)*3600 + (substr(tz,4,2)+0)*60
      ep -= tzoff
    }
    return ep
  }
  return 0
}

{
  ep = parse_date($4)
  if (ep > 0 && ep < cutoff) next

  lc = tolower($2 " " $5)
  rel = 0
  for (k = 1; k <= nkw; k++) {
    if (index(lc, kw_arr[k]) > 0) rel += 2
  }

  print rel, ep, $1, $2, $3, $4, $5
}
' "$ITEMS_FILE" | sort -t$'\t' -k1,1rn -k2,2rn > "$TMPDIR_WORK/filtered.tsv"

FILTERED=$(wc -l < "$TMPDIR_WORK/filtered.tsv" | tr -d ' ')

# --- Output ---
if $JSON_OUTPUT; then
  echo "{"
  echo "  \"feed_count\": $FEED_COUNT,"
  echo "  \"total_fetched\": $TOTAL,"
  echo "  \"filtered_count\": $FILTERED,"
  echo "  \"hours\": $HOURS,"
  if [[ -s "$ERRORS_FILE" ]]; then
    echo -n "  \"errors\": ["
    first=true
    while IFS= read -r err; do
      $first || echo -n ","
      printf '"%s"' "$(echo "$err" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      first=false
    done < "$ERRORS_FILE"
    echo "],"
  fi
  echo "  \"articles\": ["
  first=true
  while IFS=$'\t' read -r rel epoch source title link pubdate summary; do
    [[ -z "$title" ]] && continue
    $first || echo ","
    title=$(echo "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')
    link=$(echo "$link" | sed 's/\\/\\\\/g; s/"/\\"/g')
    summary=$(echo "$summary" | sed 's/\\/\\\\/g; s/"/\\"/g')
    source=$(echo "$source" | sed 's/\\/\\\\/g; s/"/\\"/g')
    pubdate=$(echo "$pubdate" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '    {"source": "%s", "title": "%s", "link": "%s", "published": "%s", "summary": "%s", "relevance": %s}' \
      "$source" "$title" "$link" "$pubdate" "$summary" "$rel"
    first=false
  done < "$TMPDIR_WORK/filtered.tsv"
  echo ""
  echo "  ]"
  echo "}"
else
  echo "Feeds: $FEED_COUNT | Fetched: $TOTAL | After filter: $FILTERED"
  if [[ -s "$ERRORS_FILE" ]]; then
    while IFS= read -r err; do echo "  [ERROR] $err"; done < "$ERRORS_FILE"
  fi
  echo ""
  i=0
  while IFS=$'\t' read -r rel epoch source title link pubdate summary; do
    [[ -z "$title" ]] && continue
    i=$((i + 1))
    echo "$i. [$source] $title"
    echo "   Link: $link"
    echo "   Date: $pubdate"
    [[ "$rel" -gt 0 ]] 2>/dev/null && echo "   Relevance: $rel"
    [[ -n "$summary" ]] && echo "   ${summary:0:200}"
    echo ""
  done < "$TMPDIR_WORK/filtered.tsv"
  [[ "$FILTERED" -eq 0 ]] && echo "No articles found in the last $HOURS hours."
fi
