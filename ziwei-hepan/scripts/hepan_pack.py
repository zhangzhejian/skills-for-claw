#!/usr/bin/env python3
import argparse
import gzip
import json
import os
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

TOPIC_WEIGHTS = {
    "love": [
        ("fuqi_first_major", 35),
        ("fude_first_major", 25),
        ("ming_first_major", 15),
        ("sihua_ji_palace", 15),
        ("gender", 10),
        ("current_daxian_palace", 5),
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
    for p in [
        Path("~/ziwei-samples/extracted/ziwei-samples-toolkit").expanduser(),
        Path("/home/zhejianzhang/ziwei-samples/extracted/ziwei-samples-toolkit"),
    ]:
        if (p / "samples-out").exists():
            return p
    return Path("~/ziwei-samples/extracted/ziwei-samples-toolkit").expanduser()


def map_year(year: int) -> int:
    return 1924 + ((year - 1924) % 60)


def sample_id(year: int, month: int, day: int, hour: int, gender: str) -> str:
    return f"{year:04d}-{month:02d}-{day:02d}-h{hour:02d}-{gender}"


def default_index_db(root: Path) -> Path:
    return root / "indexes" / "samples_meta.sqlite"


def read_chart(path: str) -> Dict[str, Any]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return data.get("chart", data)


def birth_from_args(args, prefix: str) -> Optional[Dict[str, Any]]:
    chart_path = getattr(args, f"{prefix}_chart")
    if chart_path:
        chart = read_chart(chart_path)
        b = chart.get("birthInfo") or {}
        return {**b, "_chart": chart, "_chartPath": chart_path}
    year = getattr(args, f"{prefix}_year")
    month = getattr(args, f"{prefix}_month")
    day = getattr(args, f"{prefix}_day")
    hour = getattr(args, f"{prefix}_hour")
    gender = getattr(args, f"{prefix}_gender")
    if all(v is not None for v in [year, month, day, hour, gender]):
        return {"year": year, "month": month, "day": day, "hour": hour, "gender": gender}
    return None


def lookup_sample(root: Path, birth: Dict[str, Any]) -> Dict[str, Any]:
    y = map_year(int(birth["year"]))
    m = int(birth["month"])
    p = root / "samples-out" / f"year-{y:04d}" / f"{y:04d}-{m:02d}.jsonl.gz"
    if not p.exists():
        raise FileNotFoundError(str(p))
    with gzip.open(p, "rt", encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            b = row.get("birthInfo", {})
            if int(b.get("day", -1)) == int(birth["day"]) and int(b.get("hour", -1)) == int(birth["hour"]) and b.get("gender") == birth["gender"]:
                return {"row": row, "mappedYear": y, "path": str(p)}
    raise LookupError(f"sample not found in {p}")


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
                "sihuaLuPalace": row["sihua_lu_palace"],
                "sihuaQuanPalace": row["sihua_quan_palace"],
                "sihuaJiPalace": row["sihua_ji_palace"],
                "currentDaXianPalace": row["current_daxian_palace"],
                "patterns": row["patterns"],
            },
            "topicText": text,
        })
    return out


def palace_by_name(chart: Dict[str, Any], *names: str) -> Optional[Dict[str, Any]]:
    normalized = {n.replace("宫", "") for n in names}
    return next(
        (
            p
            for p in chart.get("palaces", [])
            if str(p.get("name", "")).replace("宫", "") in normalized
        ),
        None,
    )


def major_names(palace: Optional[Dict[str, Any]]):
    if not palace:
        return []
    return [s.get("name") for s in palace.get("stars", []) if s.get("type") == "major"]


def person_pack(root: Path, index_db: Path, label: str, birth: Dict[str, Any], similar_limit: int, max_similar_chars: int) -> Dict[str, Any]:
    found = lookup_sample(root, birth)
    row = found["row"]
    chart = birth.get("_chart") or row.get("chart") or {}
    ming = palace_by_name(chart, "命", "命宫")
    fuqi = palace_by_name(chart, "夫妻", "夫妻宫")
    fude = palace_by_name(chart, "福德", "福德宫")
    topics = row.get("topics") or {}
    return {
        "label": label,
        "lookupBirthInfo": {k: birth.get(k) for k in ["year", "month", "day", "hour", "gender", "name"] if k in birth},
        "sampleBirthInfo": row.get("birthInfo"),
        "mappedYear": found["mappedYear"],
        "isExactYear": found["mappedYear"] == int(birth["year"]),
        "samplePath": found["path"],
        "palaces": {
            "ming": {"majorStars": major_names(ming), "branch": ming.get("branch") if ming else None},
            "fuqi": {"majorStars": major_names(fuqi), "branch": fuqi.get("branch") if fuqi else None},
            "fude": {"majorStars": major_names(fude), "branch": fude.get("branch") if fude else None},
        },
        "topics": {
            "overview": (topics.get("overview") or "")[:1800],
            "love": (topics.get("love") or "")[:2200],
        },
        "similarCases": {
            "overview": similar_cases(
                root, index_db, found["mappedYear"], int(birth["month"]), int(birth["day"]),
                int(birth["hour"]), birth["gender"], "overview", similar_limit, max_similar_chars,
            ),
            "love": similar_cases(
                root, index_db, found["mappedYear"], int(birth["month"]), int(birth["day"]),
                int(birth["hour"]), birth["gender"], "love", similar_limit, max_similar_chars,
            ),
        },
    }


def mirror_score(a: Dict[str, Any], b: Dict[str, Any]) -> Dict[str, Any]:
    a_fuqi = set(a["palaces"]["fuqi"]["majorStars"])
    b_ming = set(b["palaces"]["ming"]["majorStars"])
    b_fuqi = set(b["palaces"]["fuqi"]["majorStars"])
    a_ming = set(a["palaces"]["ming"]["majorStars"])
    return {
        "aFuqiMatchesBMing": sorted(a_fuqi & b_ming),
        "bFuqiMatchesAMing": sorted(b_fuqi & a_ming),
        "mutualMirror": bool(a_fuqi & b_ming) and bool(b_fuqi & a_ming),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples-root", default=os.environ.get("ZIWEI_SAMPLES_ROOT", str(default_samples_root())))
    ap.add_argument("--index-db", default=None, help="defaults to <samples-root>/indexes/samples_meta.sqlite")
    ap.add_argument("--similar-limit", type=int, default=3, help="0 disables structured similar-case retrieval")
    ap.add_argument("--max-similar-topic-chars", type=int, default=900)
    ap.add_argument("--a-chart")
    ap.add_argument("--b-chart")
    for p in ["a", "b"]:
        ap.add_argument(f"--{p}-year", type=int)
        ap.add_argument(f"--{p}-month", type=int)
        ap.add_argument(f"--{p}-day", type=int)
        ap.add_argument(f"--{p}-hour", type=int)
        ap.add_argument(f"--{p}-gender", choices=["male", "female"])
    args = ap.parse_args()

    root = Path(args.samples_root).expanduser()
    index_db = Path(args.index_db).expanduser() if args.index_db else default_index_db(root)
    a_birth = birth_from_args(args, "a")
    b_birth = birth_from_args(args, "b")
    if not a_birth or not b_birth:
        raise SystemExit("Provide --a-chart/--b-chart or complete --a-year/month/day/hour/gender and --b-* inputs")

    a = person_pack(root, index_db, "A", a_birth, args.similar_limit, args.max_similar_topic_chars)
    b = person_pack(root, index_db, "B", b_birth, args.similar_limit, args.max_similar_topic_chars)
    out = {
        "samplesRoot": str(root),
        "structuredIndex": {
            "path": str(index_db),
            "available": index_db.exists(),
            "method": "SQLite structured feature retrieval; no vector search",
        },
        "personA": a,
        "personB": b,
        "mirror": mirror_score(a, b),
        "methodologyHints": [
            "Compare 命宫 + 夫妻宫 + 福德宫 for both parties.",
            "Highest affinity when one person's 夫妻宫主星 mirrors the other's 命宫主星, especially mutually.",
            "Use sample topics as reference cases, not absolute proof.",
        ],
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
