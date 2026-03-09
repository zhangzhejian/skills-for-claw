#!/usr/bin/env python3
"""Fetch recent GitHub activity for a given repository.

Usage:
    python fetch_github.py [owner/repo] [--hours 24]

Outputs JSON with commits, pull_requests, and releases from the specified time window.
Works without authentication (public repos) but respects GITHUB_TOKEN if set.
"""

import argparse
import json
import sys
import urllib.request
import urllib.error
from datetime import datetime, timedelta, timezone


def gh_api(endpoint, token=None):
    url = f"https://api.github.com{endpoint}"
    headers = {"Accept": "application/vnd.github.v3+json", "User-Agent": "ai-agent-daily-digest"}
    if token:
        headers["Authorization"] = f"token {token}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}", "url": url}
    except Exception as e:
        return {"error": str(e), "url": url}


def fetch_commits(owner, repo, since, token=None):
    data = gh_api(f"/repos/{owner}/{repo}/commits?since={since}&per_page=30", token)
    if isinstance(data, dict) and "error" in data:
        return data
    return [
        {
            "sha": c["sha"][:7],
            "message": c["commit"]["message"].split("\n")[0],
            "author": c["commit"]["author"]["name"],
            "date": c["commit"]["author"]["date"],
        }
        for c in data
    ]


def fetch_pulls(owner, repo, token=None):
    data = gh_api(f"/repos/{owner}/{repo}/pulls?state=all&sort=updated&direction=desc&per_page=10", token)
    if isinstance(data, dict) and "error" in data:
        return data
    return [
        {
            "number": pr["number"],
            "title": pr["title"],
            "state": pr["state"],
            "author": pr["user"]["login"],
            "updated": pr["updated_at"],
        }
        for pr in data
    ]


def fetch_releases(owner, repo, token=None):
    data = gh_api(f"/repos/{owner}/{repo}/releases?per_page=3", token)
    if isinstance(data, dict) and "error" in data:
        return data
    return [
        {
            "tag": r["tag_name"],
            "name": r["name"],
            "date": r["published_at"],
            "body": (r["body"] or "")[:300],
        }
        for r in data
    ]


def main():
    parser = argparse.ArgumentParser(description="Fetch GitHub repo activity")
    parser.add_argument("repo", nargs="?", default="openclaw/openclaw", help="owner/repo (default: openclaw/openclaw)")
    parser.add_argument("--hours", type=int, default=24, help="Look back N hours (default: 24)")
    parser.add_argument("--token", default=None, help="GitHub token (or set GITHUB_TOKEN env var)")
    args = parser.parse_args()

    import os
    token = args.token or os.environ.get("GITHUB_TOKEN")
    owner, repo = args.repo.split("/", 1)
    since = (datetime.now(timezone.utc) - timedelta(hours=args.hours)).strftime("%Y-%m-%dT%H:%M:%SZ")

    result = {
        "repo": args.repo,
        "since": since,
        "commits": fetch_commits(owner, repo, since, token),
        "pull_requests": fetch_pulls(owner, repo, token),
        "releases": fetch_releases(owner, repo, token),
    }

    json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
