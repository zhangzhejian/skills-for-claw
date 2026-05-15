#!/usr/bin/env python3
import argparse
import gzip
import json
import os
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

TOPICS = {
    "overview", "personality", "love", "career", "wealth", "health",
    "family", "children", "move", "friends", "home", "spirit", "parents",
}

TOPIC_WEIGHTS = {
    "love": [
        ("fuqi_first_major", 35),
        ("fude_first_major", 25),
        ("ming_first_major", 15),
        ("sihua_ji_palace", 15),
        ("gender", 10),
        ("current_daxian_palace", 5),
    ],
    "career": [
        ("guanlu_first_major", 35),
        ("ming_first_major", 20),
        ("caibo_first_major", 15),
        ("qianyi_first_major", 10),
        ("sihua_quan_palace", 15),
        ("sihua_lu_palace", 10),
        ("gender", 5),
    ],
    "wealth": [
        ("caibo_first_major", 35),
        ("ming_first_major", 15),
        ("guanlu_first_major", 15),
        ("sihua_lu_palace", 20),
        ("sihua_ji_palace", 10),
        ("gender", 5),
    ],
    "health": [
        ("jie_branch", 30),
        ("jie_first_major", 20),
        ("jie_has_sha", 20),
        ("sihua_ji_palace", 20),
        ("gender", 10),
        ("current_daxian_palace", 10),
    ],
    "overview": [
        ("ming_first_major", 30),
        ("fude_first_major", 15),
        ("guanlu_first_major", 15),
        ("caibo_first_major", 15),
        ("sihua_ji_palace", 10),
        ("gender", 5),
    ],
}


def default_samples_root() -> Path:
    candidates = [
        Path("~/ziwei-samples/extracted/ziwei-samples-toolkit").expanduser(),
        Path("/home/zhejianzhang/ziwei-samples/extracted/ziwei-samples-toolkit"),
    ]
    for p in candidates:
        if (p / "samples-out").exists():
            return p
    return candidates[0]


def map_year_to_sample_cycle(year: int) -> int:
    # Dataset uses one 60-year cycle, observed as 1924-1983.
    return 1924 + ((year - 1924) % 60)


def sample_file(root: Path, year: int, month: int) -> Path:
    return root / "samples-out" / f"year-{year:04d}" / f"{year:04d}-{month:02d}.jsonl.gz"


def sample_id(year: int, month: int, day: int, hour: int, gender: str) -> str:
    return f"{year:04d}-{month:02d}-{day:02d}-h{hour:02d}-{gender}"


def default_index_db(root: Path) -> Path:
    return root / "indexes" / "samples_meta.sqlite"


def summarize_chart(chart: Dict[str, Any]) -> Dict[str, Any]:
    palaces = chart.get("palaces", [])
    ming_branch = chart.get("mingGongBranch")
    shen_branch = chart.get("shenGongBranch")
    ming = next((p for p in palaces if p.get("branch") == ming_branch), None)
    shen = next((p for p in palaces if p.get("branch") == shen_branch), None)

    def majors(p: Optional[Dict[str, Any]]):
        if not p:
            return []
        return [
            {
                "name": s.get("name"),
                "siHua": s.get("siHua"),
                "brightness": s.get("brightness"),
            }
            for s in p.get("stars", [])
            if s.get("type") == "major"
        ]

    return {
        "lunarInfo": chart.get("lunarInfo"),
        "mingGongBranch": ming_branch,
        "shenGongBranch": shen_branch,
        "wuxingJuName": chart.get("wuxingJuName"),
        "ziweiPos": chart.get("ziweiPos"),
        "mingPalace": {
            "name": ming.get("name") if ming else None,
            "branch": ming.get("branch") if ming else None,
            "majorStars": majors(ming),
            "isEmpty": ming.get("isEmpty") if ming else None,
            "borrowedStars": ming.get("borrowedStars") if ming else None,
        },
        "shenPalace": {
            "name": shen.get("name") if shen else None,
            "branch": shen.get("branch") if shen else None,
            "majorStars": majors(shen),
        },
        "currentDaXianIndex": chart.get("currentDaXianIndex"),
        "currentDaXian": (chart.get("daXians") or [None])[chart.get("currentDaXianIndex", -1)]
        if isinstance(chart.get("currentDaXianIndex"), int)
        and 0 <= chart.get("currentDaXianIndex") < len(chart.get("daXians") or [])
        else None,
    }


def find_sample(root: Path, year: int, month: int, day: int, hour: int, gender: str) -> Dict[str, Any]:
    mapped_year = map_year_to_sample_cycle(year)
    path = sample_file(root, mapped_year, month)
    if not path.exists():
        raise FileNotFoundError(f"Sample file not found: {path}")

    with gzip.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            b = row.get("birthInfo", {})
            if (
                int(b.get("day", -1)) == day
                and int(b.get("hour", -1)) == hour
                and b.get("gender") == gender
            ):
                return {"row": row, "path": str(path), "mappedYear": mapped_year}
    raise LookupError(f"No sample row for day={day}, hour={hour}, gender={gender} in {path}")


def read_sample_by_location(root: Path, shard: str, line_no: int) -> Dict[str, Any]:
    path = root / "samples-out" / shard
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for n, line in enumerate(f, start=1):
            if n == line_no:
                return json.loads(line)
    raise LookupError(f"No line {line_no} in {path}")


def build_similar_query(target: sqlite3.Row, topic: str, limit: int) -> Tuple[str, List[Any]]:
    weights = TOPIC_WEIGHTS.get(topic, TOPIC_WEIGHTS["overview"])
    score_terms = []
    score_params: List[Any] = []
    where_terms = ["sample_id <> ?"]
    where_params: List[Any] = [target["sample_id"]]

    for col, _weight in weights[:3]:
        value = target[col]
        if value is not None:
            where_terms.append(f"{col} = ?")
            where_params.append(value)

    for col, weight in weights:
        value = target[col]
        if value is None:
            continue
        score_terms.append(f"CASE WHEN {col} = ? THEN {weight} ELSE 0 END")
        score_params.append(value)

    target_patterns = [p for p in (target["patterns"] or "").split("|") if p][:2]
    for pattern in target_patterns:
        score_terms.append("CASE WHEN patterns LIKE ? THEN 10 ELSE 0 END")
        score_params.append(f"%|{pattern}|%")

    score_sql = " + ".join(score_terms) if score_terms else "0"
    sql = f"""
      SELECT sample_id, shard, line_no, gender,
             ming_first_major, fuqi_first_major, fude_first_major,
             guanlu_first_major, caibo_first_major, jie_first_major,
             sihua_lu_palace, sihua_quan_palace, sihua_ji_palace,
             current_daxian_palace, patterns,
             ({score_sql}) AS score
      FROM samples
      WHERE {' AND '.join(where_terms)}
      ORDER BY score DESC, sample_id
      LIMIT {int(limit)}
    """
    return sql, score_params + where_params


def similar_cases(
    root: Path,
    index_db: Path,
    mapped_year: int,
    month: int,
    day: int,
    hour: int,
    gender: str,
    topic: str,
    limit: int,
    max_topic_chars: int,
) -> List[Dict[str, Any]]:
    if limit <= 0 or not index_db.exists():
        return []
    sid = sample_id(mapped_year, month, day, hour, gender)
    conn = sqlite3.connect(index_db)
    conn.row_factory = sqlite3.Row
    target = conn.execute("SELECT * FROM samples WHERE sample_id = ?", (sid,)).fetchone()
    if not target:
        conn.close()
        return []
    sql, params = build_similar_query(target, topic, limit)
    rows = conn.execute(sql, params).fetchall()
    conn.close()

    out = []
    for row in rows:
        sample = read_sample_by_location(root, row["shard"], row["line_no"])
        text = (sample.get("topics") or {}).get(topic, "")
        if max_topic_chars and len(text) > max_topic_chars:
            text = text[:max_topic_chars] + "\n...[truncated]"
        out.append({
            "sampleId": row["sample_id"],
            "score": row["score"],
            "shard": row["shard"],
            "lineNo": row["line_no"],
            "features": {
                "gender": row["gender"],
                "ming": row["ming_first_major"],
                "fuqi": row["fuqi_first_major"],
                "fude": row["fude_first_major"],
                "guanlu": row["guanlu_first_major"],
                "caibo": row["caibo_first_major"],
                "jie": row["jie_first_major"],
                "sihuaLuPalace": row["sihua_lu_palace"],
                "sihuaQuanPalace": row["sihua_quan_palace"],
                "sihuaJiPalace": row["sihua_ji_palace"],
                "currentDaXianPalace": row["current_daxian_palace"],
                "patterns": row["patterns"],
            },
            "topicText": text,
        })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples-root", default=os.environ.get("ZIWEI_SAMPLES_ROOT", str(default_samples_root())))
    ap.add_argument("--year", type=int, required=True)
    ap.add_argument("--month", type=int, required=True)
    ap.add_argument("--day", type=int, required=True)
    ap.add_argument("--hour", type=int, required=True)
    ap.add_argument("--gender", choices=["male", "female"], required=True)
    ap.add_argument("--topic", choices=sorted(TOPICS), default="overview")
    ap.add_argument("--max-topic-chars", type=int, default=3000)
    ap.add_argument("--index-db", default=None, help="defaults to <samples-root>/indexes/samples_meta.sqlite")
    ap.add_argument("--similar-limit", type=int, default=5, help="0 disables structured similar-case retrieval")
    ap.add_argument("--max-similar-topic-chars", type=int, default=1200)
    args = ap.parse_args()

    root = Path(args.samples_root).expanduser()
    index_db = Path(args.index_db).expanduser() if args.index_db else default_index_db(root)
    found = find_sample(root, args.year, args.month, args.day, args.hour, args.gender)
    row = found["row"]
    text = (row.get("topics") or {}).get(args.topic, "")
    if args.max_topic_chars and len(text) > args.max_topic_chars:
        text = text[: args.max_topic_chars] + "\n...[truncated]"

    out = {
        "lookupBirthInfo": {
            "year": args.year,
            "month": args.month,
            "day": args.day,
            "hour": args.hour,
            "gender": args.gender,
        },
        "sampleBirthInfo": row.get("birthInfo"),
        "mappedYear": found["mappedYear"],
        "isExactYear": found["mappedYear"] == args.year,
        "samplePath": found["path"],
        "system": row.get("system"),
        "chartSummary": summarize_chart(row.get("chart") or {}),
        "topic": args.topic,
        "topicText": text,
        "structuredIndex": {
            "path": str(index_db),
            "available": index_db.exists(),
            "method": "SQLite structured feature retrieval; no vector search",
        },
        "similarCases": similar_cases(
            root=root,
            index_db=index_db,
            mapped_year=found["mappedYear"],
            month=args.month,
            day=args.day,
            hour=args.hour,
            gender=args.gender,
            topic=args.topic,
            limit=args.similar_limit,
            max_topic_chars=args.max_similar_topic_chars,
        ),
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
