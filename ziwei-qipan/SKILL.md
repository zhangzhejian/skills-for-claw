---
name: ziwei-qipan
description: Generate Ziwei Doushu natal charts from birth information using the local ziwei-doushu project. Use when the user asks to 起盘, 排盘, generate a Ziwei chart, produce a chart JSON, or create an inspectable HTML chart. Supports shell-scripted output and prefers deterministic project code over LLM calculation.
---

# Ziwei Qipan

Use this skill to generate a Ziwei Doushu chart from birth data. Do not let the model calculate stars manually. Always use the project algorithm when available.

## Inputs

Required:
- Gregorian `year`, `month`, `day`
- clock time: `clock-hour` `0-23` and `clock-minute` `0-59`
- `gender`: `male` or `female`

Optional:
- `name`
- `city`
- `longitude`
- `hour-branch`: expert override for final branch index `0-11` where `0=子, 1=丑, ... 11=亥`
- `unknown-time`: use only when birth time is unavailable; the script uses 子时 as a deterministic placeholder and marks the output as imprecise
- output directory

## Workflow

1. Locate the `ziwei-doushu` repo. Prefer the current working directory if it contains `lib/ziwei/algorithm.ts`; otherwise use `--repo`.
2. Run `scripts/qipan.sh`.
3. Return the generated JSON path and HTML path.
4. Treat the JSON as the authoritative chart data. Treat the HTML as a user-inspection artifact.

## Output Format

Final user-facing output must be Markdown.

Use:
- a short summary sentence
- bullet list for generated artifacts
- fenced code blocks for commands or JSON snippets
- Markdown links or inline paths for files

Do not return raw JSON as the final answer unless the user explicitly asks for JSON. The script JSON is an intermediate artifact; summarize it in Markdown.

## Script

```bash
~/.codex/skills/ziwei-qipan/scripts/qipan.sh \
  --repo /Users/zhejianzhang/PrivateProject/ziwei-doushu \
  --out /tmp/ziwei-chart \
  --name "示例" \
  --year 1990 --month 3 --day 15 \
  --clock-hour 11 --clock-minute 30 --gender male \
  --city 上海 --longitude 121.47
```

Outputs:
- `chart.json`: full `ZiweiChart`
- `chart.html`: standalone, clickable 12-palace view

## HTML vs Image

Prefer HTML over image for first output because it preserves structured data and supports palace click inspection without browser automation. Generate a screenshot only when the user explicitly asks for an image or share-card style output.

## Notes

- If `node_modules` is missing, install project dependencies before running.
- Prefer `--clock-hour/--clock-minute` for user-provided times. The script applies true-solar-time conversion and late-zi next-day adjustment before calling the project algorithm.
- Use `--hour-branch` only when the caller already has a verified final branch index.
