#!/usr/bin/env python3
"""Fetch recent papers from arxiv API by categories and keywords."""

import argparse
import json
import sys
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone


ARXIV_API = "http://export.arxiv.org/api/query"
NS = {"atom": "http://www.w3.org/2005/Atom", "arxiv": "http://arxiv.org/schemas/atom"}


def build_query(categories: list[str], keywords: list[str]) -> str:
    """Build arxiv API search query string."""
    parts = []

    # Category filter
    if categories:
        cat_query = " OR ".join(f"cat:{c}" for c in categories)
        parts.append(f"({cat_query})")

    # Keyword filter (search in title and abstract)
    if keywords:
        kw_parts = []
        for kw in keywords:
            kw = kw.strip()
            if " " in kw:
                kw_parts.append(f'ti:"{kw}" OR abs:"{kw}"')
            else:
                kw_parts.append(f"ti:{kw} OR abs:{kw}")
        kw_query = " OR ".join(f"({k})" for k in kw_parts)
        parts.append(f"({kw_query})")

    if len(parts) == 2:
        return f"{parts[0]} AND {parts[1]}"
    elif len(parts) == 1:
        return parts[0]
    else:
        return "all"


def fetch_papers(query: str, max_results: int, hours: int) -> list[dict]:
    """Fetch papers from arxiv API and filter by date."""
    # Fetch in batches to get more results if needed
    all_entries = []
    batch_size = min(max_results, 200)
    start = 0

    while start < max_results:
        params = {
            "search_query": query,
            "start": start,
            "max_results": batch_size,
            "sortBy": "submittedDate",
            "sortOrder": "descending",
        }

        url = f"{ARXIV_API}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url, headers={"User-Agent": "arxiv-daily-digest/1.0"})

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
        except Exception as e:
            print(f"Error fetching batch at start={start}: {e}", file=sys.stderr)
            break

        root = ET.fromstring(data)
        entries = root.findall("atom:entry", NS)

        if not entries:
            break

        all_entries.extend(entries)

        # If we got fewer than requested, no more results
        if len(entries) < batch_size:
            break

        start += batch_size

    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)

    papers = []
    for entry in all_entries:
        title = entry.find("atom:title", NS)
        if title is None:
            continue
        title_text = " ".join(title.text.strip().split())

        # Parse published date (use updated date as fallback, since arxiv
        # sometimes has papers with old published dates but recent updates)
        published = entry.find("atom:published", NS)
        updated = entry.find("atom:updated", NS)
        if published is None:
            continue

        pub_date = datetime.fromisoformat(published.text.replace("Z", "+00:00"))
        upd_date = None
        if updated is not None:
            upd_date = datetime.fromisoformat(updated.text.replace("Z", "+00:00"))

        # Use the most recent date for filtering
        effective_date = max(pub_date, upd_date) if upd_date else pub_date

        if effective_date < cutoff:
            continue

        # Extract authors
        authors = []
        for author in entry.findall("atom:author", NS):
            name = author.find("atom:name", NS)
            if name is not None:
                authors.append(name.text.strip())

        # Extract abstract
        summary = entry.find("atom:summary", NS)
        abstract = " ".join(summary.text.strip().split()) if summary is not None else ""

        # Extract arxiv ID and link
        entry_id = entry.find("atom:id", NS)
        arxiv_id = entry_id.text.strip().split("/abs/")[-1] if entry_id is not None else ""
        link = f"https://arxiv.org/abs/{arxiv_id}"

        # Extract categories
        categories = []
        for cat in entry.findall("atom:category", NS):
            term = cat.get("term", "")
            if term:
                categories.append(term)

        # Extract primary category
        primary_cat = entry.find("arxiv:primary_category", NS)
        primary = primary_cat.get("term", "") if primary_cat is not None else ""

        # Extract PDF link
        pdf_link = ""
        for lnk in entry.findall("atom:link", NS):
            if lnk.get("title") == "pdf":
                pdf_link = lnk.get("href", "")
                break

        papers.append({
            "title": title_text,
            "authors": authors,
            "abstract": abstract,
            "arxiv_id": arxiv_id,
            "link": link,
            "pdf_link": pdf_link,
            "published": pub_date.isoformat(),
            "updated": upd_date.isoformat() if upd_date else pub_date.isoformat(),
            "categories": categories,
            "primary_category": primary,
        })

    return papers


def main():
    parser = argparse.ArgumentParser(description="Fetch recent arxiv papers")
    parser.add_argument("--categories", type=str, default="", help="Comma-separated arxiv categories")
    parser.add_argument("--keywords", type=str, default="", help="Comma-separated keywords")
    parser.add_argument("--max-results", type=int, default=200, help="Max results per query")
    parser.add_argument("--hours", type=int, default=72, help="Hours to look back")
    args = parser.parse_args()

    categories = [c.strip() for c in args.categories.split(",") if c.strip()]
    keywords = [k.strip() for k in args.keywords.split(",") if k.strip()]

    if not categories and not keywords:
        print("Error: at least one of --categories or --keywords is required", file=sys.stderr)
        sys.exit(1)

    query = build_query(categories, keywords)
    print(f"Query: {query}", file=sys.stderr)

    papers = fetch_papers(query, args.max_results, args.hours)
    print(f"Found {len(papers)} papers in the last {args.hours} hours", file=sys.stderr)

    # Deduplicate by arxiv_id
    seen = set()
    unique = []
    for p in papers:
        if p["arxiv_id"] not in seen:
            seen.add(p["arxiv_id"])
            unique.append(p)

    if len(unique) < len(papers):
        print(f"After dedup: {len(unique)} unique papers", file=sys.stderr)

    json.dump(unique, sys.stdout, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
