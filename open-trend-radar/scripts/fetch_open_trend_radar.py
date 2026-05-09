#!/usr/bin/env python3
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urldefrag

import requests
from bs4 import BeautifulSoup


DEFAULT_URL = "https://open-trend-radar.test.rd.ai/"


def clean_text(node):
    if not node:
        return ""
    return " ".join(node.get_text(" ", strip=True).split())


def strip_count(text):
    return clean_text(text).replace(" 条", "").strip()


def fetch_html(url, timeout):
    request_url = urldefrag(url)[0] or DEFAULT_URL
    response = requests.get(
        request_url,
        timeout=timeout,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0 Safari/537.36"
            )
        },
    )
    response.raise_for_status()
    response.encoding = "utf-8"
    return request_url, response.text


def parse_header(soup):
    report = {}
    for item in soup.select(".header-info .info-item"):
        label = clean_text(item.select_one(".info-label"))
        value = clean_text(item.select_one(".info-value"))
        if label:
            report[label] = value
    title = clean_text(soup.select_one(".header-title"))
    if title:
        report["标题"] = title
    return report


def parse_news_item(node):
    link = node.select_one(".news-title a")
    return {
        "number": clean_text(node.select_one(".news-number")),
        "source": clean_text(node.select_one(".source-name")),
        "rank": clean_text(node.select_one(".rank-num")),
        "time": clean_text(node.select_one(".time-info")),
        "count": clean_text(node.select_one(".count-info")),
        "title": clean_text(link),
        "url": link.get("href", "") if link else "",
    }


def parse_rss_item(node, feed_name=""):
    link = node.select_one(".rss-title a")
    authors = [clean_text(author) for author in node.select(".rss-author")]
    return {
        "feed": feed_name,
        "time": clean_text(node.select_one(".rss-time")),
        "authors": [author for author in authors if author],
        "title": clean_text(link),
        "url": link.get("href", "") if link else "",
    }


def parse_rss_section(section):
    feeds = []
    for group in section.select(".feed-group"):
        feed_name = clean_text(group.select_one(".feed-name"))
        feed_count = strip_count(group.select_one(".feed-count"))
        items = [parse_rss_item(item, feed_name) for item in group.select(".rss-item")]
        feeds.append({"feed": feed_name, "count": feed_count, "items": items})
    return {
        "title": clean_text(section.select_one(".rss-section-title")),
        "count": strip_count(section.select_one(".rss-section-count")),
        "feeds": feeds,
    }


def parse_hotlists(soup):
    groups = []
    for group in soup.select(".word-group[data-tab-index]"):
        category = clean_text(group.select_one(".word-name"))
        count = strip_count(group.select_one(".word-count"))
        items = [parse_news_item(item) for item in group.select(".news-item")]
        groups.append(
            {
                "tab_index": group.get("data-tab-index", ""),
                "category": category,
                "count": count,
                "items": items,
            }
        )
    return groups


def parse_standalone(soup):
    section = soup.select_one(".standalone-section")
    if not section:
        return {"title": "", "count": "", "items": []}
    return {
        "title": clean_text(section.select_one(".standalone-section-title")),
        "count": strip_count(section.select_one(".standalone-section-count")),
        "items": [parse_news_item(item) for item in section.select(".news-item")],
    }


def parse_page(html, source_url):
    soup = BeautifulSoup(html, "html.parser")
    rss_sections = soup.select(".rss-section")
    return {
        "source_url": source_url,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "report": parse_header(soup),
        "failed_platforms": [clean_text(item) for item in soup.select(".error-section .error-item")],
        "rss_new": parse_rss_section(rss_sections[0]) if rss_sections else {"feeds": []},
        "hotlists": parse_hotlists(soup),
        "rss_updates": parse_rss_section(rss_sections[1]) if len(rss_sections) > 1 else {"feeds": []},
        "standalone": parse_standalone(soup),
    }


def filter_data(data, category, top):
    if category:
        data["hotlists"] = [
            group
            for group in data["hotlists"]
            if group["tab_index"] == category or group["category"] == category
        ]
        if not category.isdigit():
            for section_name in ("rss_new", "rss_updates"):
                section = data.get(section_name, {})
                section["feeds"] = [
                    feed for feed in section.get("feeds", []) if feed.get("feed") == category
                ]
    if top is not None:
        for group in data["hotlists"]:
            group["items"] = group["items"][:top]
        for section_name in ("rss_new", "rss_updates"):
            for feed in data.get(section_name, {}).get("feeds", []):
                feed["items"] = feed["items"][:top]
        data["standalone"]["items"] = data["standalone"]["items"][:top]
    return data


def render_markdown(data):
    lines = ["# Open Trend Radar", ""]
    if data["report"]:
        lines.append("## 报告信息")
        for key, value in data["report"].items():
            lines.append(f"- **{key}**: {value}")
        lines.append("")

    if data["failed_platforms"]:
        lines.append("## 请求失败平台")
        lines.append(", ".join(data["failed_platforms"]))
        lines.append("")

    if data["rss_new"].get("feeds"):
        lines.append(f"## {data['rss_new'].get('title') or 'RSS 新增更新'}")
        append_rss_markdown(lines, data["rss_new"])

    lines.append("## 热点分组")
    for group in data["hotlists"]:
        lines.append(f"### {group['category']} ({len(group['items'])}/{group['count']})")
        append_news_markdown(lines, group["items"])

    if data["rss_updates"].get("feeds"):
        lines.append(f"## {data['rss_updates'].get('title') or 'RSS 订阅更新'}")
        append_rss_markdown(lines, data["rss_updates"])

    if data["standalone"].get("items"):
        lines.append(f"## {data['standalone'].get('title') or '独立展示区'}")
        append_news_markdown(lines, data["standalone"]["items"])

    return "\n".join(lines).rstrip() + "\n"


def append_news_markdown(lines, items):
    if not items:
        lines.append("无数据")
        lines.append("")
        return
    for item in items:
        meta = " | ".join(
            value
            for value in [item.get("source"), item.get("rank"), item.get("time"), item.get("count")]
            if value
        )
        prefix = f"{item['number']}. " if item.get("number") else "- "
        lines.append(f"{prefix}[{item['title']}]({item['url']})")
        if meta:
            lines.append(f"   - {meta}")
    lines.append("")


def append_rss_markdown(lines, section):
    for feed in section.get("feeds", []):
        lines.append(f"### {feed['feed']} ({len(feed['items'])}/{feed['count']})")
        for item in feed["items"]:
            meta = " | ".join(value for value in [item.get("time"), ", ".join(item.get("authors", []))] if value)
            lines.append(f"- [{item['title']}]({item['url']})")
            if meta:
                lines.append(f"  - {meta}")
        lines.append("")


def main():
    parser = argparse.ArgumentParser(description="Fetch and parse Open Trend Radar HTML data.")
    parser.add_argument("--url", default=DEFAULT_URL, help="TrendRadar page URL. Hash fragments are ignored.")
    parser.add_argument("--format", choices=["json", "md"], default="json", help="Output format.")
    parser.add_argument("--category", help="Filter hotlist by category name or tab index.")
    parser.add_argument("--top", type=int, help="Limit items per group/feed.")
    parser.add_argument("--timeout", type=int, default=30, help="HTTP timeout in seconds.")
    parser.add_argument("--save-html", help="Save raw HTML to this path.")
    args = parser.parse_args()

    try:
        source_url, html = fetch_html(args.url, args.timeout)
        if args.save_html:
            Path(args.save_html).write_text(html, encoding="utf-8")
        data = filter_data(parse_page(html, source_url), args.category, args.top)
        if args.format == "json":
            print(json.dumps(data, ensure_ascii=False, indent=2))
        else:
            print(render_markdown(data), end="")
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
