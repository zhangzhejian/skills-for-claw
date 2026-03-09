#!/usr/bin/env python3
"""Fetch and filter recent AI Agent news from curated RSS feeds.

Usage:
    python fetch_rss.py [--hours 24] [--json] [--verbose]

Outputs filtered articles from the last N hours. Default output is human-readable;
use --json for structured JSON output.
"""

import argparse
import json
import sys
import xml.etree.ElementTree as ET
import urllib.request
import urllib.error
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime


# Curated, verified RSS feeds for AI Agent news.
# Each entry: (name, url, category)
# Categories: "general" = broad AI/tech news, "official" = vendor blogs
FEEDS = [
    ("Hacker News - AI Agent", "https://hnrss.org/newest?q=AI+agent&count=30", "general"),
    ("TechCrunch AI", "https://techcrunch.com/category/artificial-intelligence/feed/", "general"),
    ("VentureBeat AI", "https://venturebeat.com/feed/", "general"),
    ("MIT Technology Review", "https://www.technologyreview.com/feed/", "general"),
    ("OpenAI Blog", "https://openai.com/blog/rss.xml", "official"),
    ("Google AI Blog", "https://blog.google/technology/ai/rss/", "official"),
]

# Keywords to boost relevance ranking (case-insensitive)
AGENT_KEYWORDS = [
    "agent", "agentic", "autonomous", "tool use", "function calling",
    "mcp", "claude", "gpt", "gemini", "copilot",
    "langchain", "langgraph", "autogen", "crewai", "openai",
    "anthropic", "coding agent", "ai assistant",
]


def fetch_feed(name, url, timeout=15):
    """Fetch and parse a single RSS feed. Returns list of article dicts."""
    headers = {"User-Agent": "ai-agent-daily-digest/1.0"}
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
        return [], f"{name}: {e}"

    try:
        root = ET.fromstring(raw)
    except ET.ParseError as e:
        return [], f"{name}: XML parse error: {e}"

    articles = []
    # Handle both RSS 2.0 (<item>) and Atom (<entry>) feeds
    ns = {"atom": "http://www.w3.org/2005/Atom"}

    # RSS 2.0
    for item in root.iter("item"):
        title = _text(item, "title")
        link = _text(item, "link")
        pub_date_str = _text(item, "pubDate")
        description = _text(item, "description") or ""

        pub_date = _parse_date(pub_date_str)
        articles.append({
            "source": name,
            "title": title,
            "link": link,
            "published": pub_date.isoformat() if pub_date else pub_date_str,
            "published_dt": pub_date,
            "summary": _clean_html(description)[:500],
        })

    # Atom
    if not articles:
        for entry in root.iter("{http://www.w3.org/2005/Atom}entry"):
            title = _text(entry, "{http://www.w3.org/2005/Atom}title")
            link_el = entry.find("{http://www.w3.org/2005/Atom}link")
            link = link_el.get("href", "") if link_el is not None else ""
            updated = _text(entry, "{http://www.w3.org/2005/Atom}updated") or _text(entry, "{http://www.w3.org/2005/Atom}published")
            summary = _text(entry, "{http://www.w3.org/2005/Atom}summary") or ""

            pub_date = _parse_date(updated)
            articles.append({
                "source": name,
                "title": title,
                "link": link,
                "published": pub_date.isoformat() if pub_date else updated,
                "published_dt": pub_date,
                "summary": _clean_html(summary)[:500],
            })

    return articles, None


def _text(element, tag):
    child = element.find(tag)
    return child.text.strip() if child is not None and child.text else ""


def _parse_date(date_str):
    if not date_str:
        return None
    try:
        return parsedate_to_datetime(date_str)
    except Exception:
        pass
    # Try ISO format
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d"):
        try:
            dt = datetime.strptime(date_str.strip(), fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt
        except ValueError:
            continue
    return None


def _clean_html(text):
    """Rough HTML tag removal."""
    import re
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def relevance_score(article):
    """Score article relevance to AI Agent topics. Higher = more relevant."""
    text = f"{article.get('title', '')} {article.get('summary', '')}".lower()
    score = sum(2 if kw in text else 0 for kw in AGENT_KEYWORDS)
    return score


def main():
    parser = argparse.ArgumentParser(description="Fetch AI Agent news from RSS feeds")
    parser.add_argument("--hours", type=int, default=24, help="Look back N hours (default: 24)")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--verbose", action="store_true", help="Show fetch errors and stats")
    args = parser.parse_args()

    cutoff = datetime.now(timezone.utc) - timedelta(hours=args.hours)
    all_articles = []
    errors = []

    for name, url, category in FEEDS:
        articles, err = fetch_feed(name, url)
        if err:
            errors.append(err)
            continue
        for a in articles:
            a["category"] = category
        all_articles.extend(articles)

    # Filter by time
    filtered = []
    for a in all_articles:
        dt = a.get("published_dt")
        if dt and dt >= cutoff:
            filtered.append(a)
        elif dt is None:
            # Keep articles with unparseable dates (let the model decide)
            a["date_uncertain"] = True
            filtered.append(a)

    # Score and sort by relevance, then by date
    for a in filtered:
        a["relevance"] = relevance_score(a)
    filtered.sort(key=lambda a: (a["relevance"], a.get("published_dt") or cutoff), reverse=True)

    # Remove internal fields before output
    for a in filtered:
        a.pop("published_dt", None)

    if args.json:
        output = {
            "feed_count": len(FEEDS),
            "total_fetched": len(all_articles),
            "filtered_count": len(filtered),
            "hours": args.hours,
            "articles": filtered,
        }
        if args.verbose and errors:
            output["errors"] = errors
        json.dump(output, sys.stdout, indent=2, ensure_ascii=False)
        print()
    else:
        if args.verbose:
            print(f"Feeds: {len(FEEDS)} | Fetched: {len(all_articles)} | After filter: {len(filtered)}")
            for err in errors:
                print(f"  [ERROR] {err}")
            print()

        if not filtered:
            print("No articles found in the last {} hours.".format(args.hours))
            return

        for i, a in enumerate(filtered, 1):
            print(f"{i}. [{a['source']}] {a['title']}")
            print(f"   Link: {a['link']}")
            print(f"   Date: {a['published']}")
            if a.get("relevance", 0) > 0:
                print(f"   Relevance: {a['relevance']}")
            if a["summary"]:
                print(f"   {a['summary'][:200]}")
            print()


if __name__ == "__main__":
    main()
