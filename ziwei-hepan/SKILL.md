---
name: ziwei-hepan
description: Perform Ziwei Doushu relationship or partnership analysis by preparing two charts, reusing existing chart JSON when available, retrieving sample cases for both parties, and applying hepan methodology. Use when the user asks for 合盘, 姻缘分析, relationship compatibility, marriage matching, partnership matching, or dual-chart analysis.
---

# Ziwei Hepan

Use this skill for two-person Ziwei analysis. Never compare only narrative text; compare chart structure first.

## Workflow

1. Get or generate both charts.
   - If a chart JSON already exists, use it.
   - Otherwise use `ziwei-qipan`.
2. Build a compact hepan case pack with `scripts/hepan_pack.py`.
   - Prefer `indexes/samples_meta.sqlite` when available under the sample toolkit root.
   - The index retrieves structured similar cases for each party's `love` and `overview` topics without vector search.
3. Analyze these dimensions:
   - each person's 命宫, 夫妻宫, 福德宫
   - whether A's spouse palace stars mirror B's ming palace stars, and vice versa
   - four transformations affecting relationship fields when available
   - current daxian direction if present
   - exact mapped sample `love` and `overview` text for both parties
   - structured similar cases for both parties as style/case references
4. Use `lib/ziwei/heming-knowledge.ts` from the project as methodology when available.
5. Give practical conclusions with uncertainty. Do not claim deterministic fate.

## Script

With existing chart JSON:

```bash
~/.codex/skills/ziwei-hepan/scripts/hepan_pack.py \
  --samples-root ~/ziwei-samples/extracted/ziwei-samples-toolkit \
  --a-chart /tmp/a/chart.json \
  --b-chart /tmp/b/chart.json \
  --similar-limit 3
```

With birth info:

```bash
~/.codex/skills/ziwei-hepan/scripts/hepan_pack.py \
  --a-year 1990 --a-month 3 --a-day 15 --a-hour 6 --a-gender male \
  --b-year 1992 --b-month 8 --b-day 20 --b-hour 3 --b-gender female \
  --similar-limit 3
```

The script returns a JSON pack with:
- `personA` / `personB` palace summaries
- exact mapped `overview` and `love` topic text
- `personA.similarCases` / `personB.similarCases` from the structured index
- mirror checks between one party's 夫妻宫 and the other's 命宫

Use the pack as evidence for the final answer. Treat `similarCases` as reference cases and writing support, not direct proof.

## Answer Shape

Prefer:
- 总体匹配度
- 关键合拍点
- 关键冲突点
- 婚恋/合作建议
- 样本案例依据

Avoid:
- "必然离婚", "必死", or other absolute claims
- medical, legal, financial certainty
- pretending sampled text is direct proof for a different real person
- running vector retrieval over the full 518,400 samples before trying structured feature retrieval
