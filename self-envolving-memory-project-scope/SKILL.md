---
name: self-envolving-memory-project-scope
description: Project-scoped memory for Codex and Claude Code agents that store and retrieve durable context from a repository-local .memory path, with evidence-backed memory patches, retrieval context generation, objective fact verification records, memory item conflict detection and merging, selective forgetting, and git worktree divergence detection and merging. Use when setting up per-project agent memory, sharing memory between Codex and Claude Code, reading or updating .memory, auditing factual memories, resolving contradictory memory items, forgetting selected memories, or handling memory across multiple worktrees. Also use when the user corrects a remembered project fact, says the agent repeated a previous mistake, says prior context or memory was ignored, says "I already told you", or reports a regression where something previously handled successfully failed this time.
---

# Self Envolving Memory Project Scope

Use this skill to keep agent memory local to one software project instead of one global assistant profile. The contract is:

- Treat `<project>/.memory` as the only memory API path for Codex and Claude Code.
- Read `.memory` before acting when the user asks for project context, prior decisions, preferences, or memory-aware behavior.
- Write durable memory only through evidence-backed events and patches.
- Treat objective facts as structured claims when they need verification or conflict checks.
- Keep one logical memory for all worktrees of the same git repository.

## Quick Start

From this skill directory, use:

```bash
bash scripts/project_memory.sh init --project /path/to/repo --mode shared
bash scripts/project_memory.sh context --project /path/to/repo
bash scripts/project_memory.sh status --project /path/to/repo
```

For the current working directory, omit `--project`.

`--mode shared` is the preferred mode for git worktrees. It creates one real store under the git common directory and makes each worktree's `.memory` path point at it. This keeps the project-facing path stable while avoiding per-worktree memory forks.

Use `--mode local` only when the project must keep a physical `.memory` directory in that exact worktree, such as a non-git project or a repo where symlinks are not acceptable.

## Retrieval Workflow

1. Locate the project root with `bash scripts/project_memory.sh root`.
2. Initialize if needed with `bash scripts/project_memory.sh init --mode shared`.
3. Generate retrieval context with `bash scripts/project_memory.sh context`.
4. Use active memories only. Ignore deprecated items unless diagnosing history.
5. If memory is missing, wrong, stale, or conflicting, record an event and propose a patch before applying it.

For Claude Code headless runs, prepend the generated context to the task prompt:

```bash
memory_context="$(bash scripts/project_memory.sh context --project /path/to/repo)"
printf "%s\n\nTask: %s\n" "$memory_context" "implement the requested change" | claude -p
```

For Codex, run the same `context` command before project-specific work when the skill triggers.

## Updating Memory

Use the wrapper for the common operations; it resolves the project store first and then delegates to `memory_ops.sh`.

```bash
bash scripts/project_memory.sh event --type feedback --text "User corrected the deployment target."
bash scripts/project_memory.sh patch --kind add_memory --reason "Stable project preference" --after "Deploy previews target staging by default."
bash scripts/project_memory.sh apply --patch patch_... --memory-type project --scope project --confidence 0.8 --validated
```

Store current task state in `.memory/working.md`. Store durable facts in `.memory/long_term/facts.jsonl`. Keep raw observations append-only in `.memory/events.jsonl`.

Read `references/memory-layout.md` before changing the layout, writing a custom merge, or resolving conflicts.

## Memory Quality

Read `references/memory-quality.md` before auditing facts, resolving contradictions, or forgetting memory.

Objective fact validation is evidence recording, not automatic truth discovery. The agent must inspect the relevant source of truth first, then record the result:

```bash
bash scripts/project_memory.sh claim --memory mem_... --subject deploy.preview --predicate target --value staging
bash scripts/project_memory.sh verify --memory mem_... --verdict verified --evidence "Checked deployment config in deploy.yaml" --ref deploy.yaml
```

Find structured contradictions:

```bash
bash scripts/project_memory.sh conflicts
bash scripts/project_memory.sh audit
```

Merge two memory items only after choosing the surviving statement:

```bash
bash scripts/project_memory.sh merge-items --into mem_new --from mem_old --after "Deploy previews target staging by default." --reason "Resolved duplicate/conflicting deployment target memories."
```

Forget selectively by deprecating the item or suppressing it from retrieval:

```bash
bash scripts/project_memory.sh forget --memory mem_... --reason "No longer relevant after migration." --mode deprecate
bash scripts/project_memory.sh forget --memory mem_... --reason "Too broad for normal retrieval." --mode suppress
```

Selective forgetting is retrieval forgetting by default. It preserves event history and patch history for reversibility; it is not a secure erasure mechanism for secrets.

## Worktree Rules

Multiple git worktrees can fork memory if each worktree has an independent physical `.memory` directory. Avoid this by default:

```bash
bash scripts/project_memory.sh init --mode shared
```

Run this in every worktree that should share memory. Then check:

```bash
bash scripts/project_memory.sh status
```

If all worktrees report the same real store path, memory is not forked.

If memory has already forked, merge another store into the current project store:

```bash
bash scripts/project_memory.sh merge --from /path/to/other-worktree/.memory
```

The merge is conservative:

- JSONL files are unioned by `id`; exact duplicates are skipped.
- Same `id` with different JSON is not auto-resolved; both versions are saved under `.memory/meta/conflicts/`.
- Markdown files are not auto-merged when both sides changed; the incoming version is saved under `.memory/meta/conflicts/`.
- A merge event is appended to `.memory/events.jsonl`.

After a merge, inspect conflicts before trusting affected memories.
