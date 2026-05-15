---
name: ziwei-jiepan
description: Read and interpret an existing Ziwei Doushu chart with case-backed retrieval from the 518,400-sample dataset. Use when the user asks to 解盘, analyze a generated chart, search sample cases, retrieve topic interpretations, or ground an AI reading in Ziwei sample data and rule-based chart features.
---

# Ziwei Jiepan

Use this skill after a chart has been generated. Keep deterministic chart data separate from narrative interpretation.

## Data Sources

Sample dataset default roots:
- `~/ziwei-samples/extracted/ziwei-samples-toolkit`
- `/home/zhejianzhang/ziwei-samples/extracted/ziwei-samples-toolkit` on the VM

The sample layout is:

```text
samples-out/year-YYYY/YYYY-MM.jsonl.gz
indexes/samples_meta.sqlite
```

Each JSONL row has:
- `birthInfo`
- `chart`
- `topics`
- `system`

## Workflow

1. If the user has not generated a chart, use `ziwei-qipan` first.
2. Use `scripts/sample_lookup.py` to retrieve a compact case pack.
   - Prefer the structured SQLite index at `indexes/samples_meta.sqlite` when it exists.
   - The index was built from all 518,400 samples and supports rule-scored similar-case retrieval without vectors.
   - Exact lookup still maps birth year into the 1924-1983 sample cycle, then similar cases are scored by chart features.
3. Ask for only the needed topic: `overview`, `career`, `love`, `wealth`, `health`, etc.
4. Compose the reading from:
   - current chart facts
   - detected patterns if present
   - exact mapped sample topic text
   - `similarCases` from the structured index
   - any project knowledge such as `patterns.ts`, classics, or `heming-knowledge.ts`
5. State uncertainty when the sample year was mapped into the 60-year cycle.

## Script

```bash
~/.codex/skills/ziwei-jiepan/scripts/sample_lookup.py \
  --samples-root ~/ziwei-samples/extracted/ziwei-samples-toolkit \
  --year 1990 --month 3 --day 15 --hour 6 --gender male \
  --topic career --max-topic-chars 2500 \
  --similar-limit 5 --max-similar-topic-chars 1200
```

The script returns JSON with:
- `lookupBirthInfo`
- `sampleBirthInfo`
- `mappedYear`
- `chartSummary`
- `topicText`
- `structuredIndex`
- `similarCases`
- `samplePath`

`similarCases` includes:
- `score`
- `sampleId`
- `shard` and `lineNo`
- chart feature summary
- same-topic text excerpt

## Guidance

- Do not paste all 13 topics into the model context unless explicitly requested.
- Prefer a concise answer with evidence: "命宫/官禄/财帛/迁移 show X; exact mapped sample and similar cases support Y."
- Treat similar cases as style and pattern references, not proof about the user's fate.
- If exact sample lookup is not possible, use the mapped-cycle sample as a reference style, not as authoritative truth.
- Do not use vector retrieval for the 518,400 samples by default; use structured feature matching first.
