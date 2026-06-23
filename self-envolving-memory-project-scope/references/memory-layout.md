# Project Memory Layout

The public memory path is always `<project>/.memory`, even when the real storage is shared by several git worktrees through a symlink.

```text
.memory/
  events.jsonl
  working.md
  long_term/
    profile.md
    facts.jsonl
    projects/
  meta/
    config.json
    fact-verifications.jsonl
    memory-system.md
    patches.jsonl
    retrieval-policy.md
    conflicts/
  evals/
    cases.jsonl
    runs.jsonl
```

## Durable Records

Use append-only JSONL for evidence and durable items:

- `events.jsonl`: raw observations, user feedback, tool results, failures, patch applications, merges.
- `long_term/facts.jsonl`: active, deprecated, superseded, and candidate memory items.
- `meta/patches.jsonl`: proposed, applied, rejected, and rolled-back memory/schema/retrieval patches.
- `meta/fact-verifications.jsonl`: objective fact checks with verdict, evidence, refs, and linked event id.
- `evals/*.jsonl`: regression cases and runs for memory behavior.

Prefer deprecating or superseding memory items over deleting them.

## Retrieval

The default retrieval context should include:

- `working.md` for active task state.
- `long_term/profile.md` for stable project profile notes.
- active `long_term/facts.jsonl` items with confidence at or above the policy floor.
- `meta/retrieval-policy.md` for conflict and ranking rules.

Do not include deprecated memories in normal retrieval.

Only the latest record per memory `id` participates in retrieval. A later `deprecated` record hides older active versions. A later active record tagged `suppress-retrieval` is also hidden from normal retrieval.

## Worktree Storage Modes

`shared` mode is preferred for git repositories:

- real store: `$(git rev-parse --git-common-dir)/self-envolving-memory-project-scope/store`
- worktree API path: `<worktree>/.memory`
- implementation: `.memory` is a symlink to the real store when possible.

This gives Codex and Claude Code the same local path in every worktree while keeping one backing store.

`local` mode creates a physical `<worktree>/.memory` directory. Use it for non-git projects, symlink-hostile environments, or intentionally isolated experiments.

## Merge Policy

Merging must preserve evidence and avoid silent overwrites.

For JSONL:

- If an incoming record has a new `id`, append it.
- If the `id` already exists with identical canonical JSON, skip it.
- If the `id` exists with different canonical JSON, write both records to `meta/conflicts/` and leave the destination unchanged.

For Markdown:

- If the destination is missing, copy the source file.
- If source and destination match exactly, skip it.
- If both differ, save the incoming file under `meta/conflicts/`; do not splice text automatically.

After every merge, append a merge event to `events.jsonl` with the source store and conflict count.
