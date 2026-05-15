---
name: ziwei-qipan
description: Generate Ziwei Doushu natal charts from birth information using the local ziwei-doushu project. Use when the user asks to 起盘, 排盘, generate a Ziwei chart, produce a chart JSON, or create an inspectable HTML chart. Supports shell-scripted output and prefers deterministic project code over LLM calculation.
---

# Ziwei Qipan

Use this skill to generate a Ziwei Doushu chart from birth data. Do not let the model calculate stars manually. Always use the project algorithm when available.

## Inputs

Required:
- Gregorian `year`, `month`, `day`
- `hour`: branch index `0-11` where `0=子, 1=丑, ... 11=亥`
- `gender`: `male` or `female`

Optional:
- `name`
- `city`
- `longitude`
- output directory

## Workflow

1. Locate the `ziwei-doushu` repo. Prefer the current working directory if it contains `lib/ziwei/algorithm.ts`; otherwise use `--repo`.
2. Run `scripts/qipan.sh`.
3. Return the generated JSON path and HTML path.
4. Treat the JSON as the authoritative chart data. Treat the HTML as a user-inspection artifact.

## Script

```bash
~/.codex/skills/ziwei-qipan/scripts/qipan.sh \
  --repo /Users/zhejianzhang/PrivateProject/ziwei-doushu \
  --out /tmp/ziwei-chart \
  --name "示例" \
  --year 1990 --month 3 --day 15 \
  --hour 6 --gender male \
  --city 上海 --longitude 121.47
```

Outputs:
- `chart.json`: full `ZiweiChart`
- `chart.html`: standalone, clickable 12-palace view

## HTML vs Image

Prefer HTML over image for first output because it preserves structured data and supports palace click inspection without browser automation. Generate a screenshot only when the user explicitly asks for an image or share-card style output.

## Notes

- If `node_modules` is missing, install project dependencies before running.
- If the user's time is clock time, convert it to a branch index before calling this script. The project `BirthForm` contains true-solar-time logic, but this script expects the final branch index.
