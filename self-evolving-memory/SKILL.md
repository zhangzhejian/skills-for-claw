---
name: self-evolving-memory
description: Design, operate, and improve an agent memory system that can diagnose memory failures from user feedback, propose versioned memory/schema/skill patches, validate them, and apply or roll them back. Use when the user asks about agent memory, long-term memory, working memory, self-improving memory, memory review, memory patches, memory evals, or evolving skills and storage from interaction feedback.
---

# Self-Evolving Memory

Use this skill when an agent needs to maintain or improve memory, not merely store facts.

The core rule: **memory changes must be evidence-backed, versioned, validated, and reversible**.

## Mental Model

Treat memory as a small database plus a patch discipline:

```text
interaction/event log -> memory items -> retrieval/use -> feedback
  -> diagnose failure -> propose patch -> verify -> apply or rollback
```

Memory has four layers:

- `events`: append-only raw observations, feedback, tool results, failures, patches.
- `working`: active task state, plans, temporary assumptions.
- `long_term`: stable facts, preferences, relationships, project context.
- `meta`: memory-system knowledge: bad memories, stale rules, failed retrievals, schema changes, skill problems.

## When Feedback Arrives

Do not immediately overwrite memory. Classify the issue first:

- `missing_memory`: should have remembered something but did not.
- `wrong_memory`: stored fact is wrong.
- `stale_memory`: once true, now outdated.
- `overgeneralized_memory`: weak evidence was turned into a broad rule.
- `underused_memory`: relevant memory existed but was not retrieved or used.
- `conflicting_memory`: two memories disagree.
- `bad_schema`: storage lacks the field or structure needed.
- `bad_retrieval`: retrieval/filtering/ranking failed.
- `bad_skill`: a skill's trigger, workflow, or output caused the failure.

See `references/diagnostics.md` for examples and decision rules.

## Patch Workflow

Every change should be expressed as a patch:

```text
observe -> diagnose -> propose -> verify -> apply -> record outcome
```

Patch types:

- `add_memory`
- `update_memory`
- `deprecate_memory`
- `merge_memories`
- `schema_patch`
- `retrieval_policy_patch`
- `skill_patch`
- `eval_patch`

Use `references/schema.md` for JSON shapes.

## Storage Layout

Default store:

```text
.memory/
  events.jsonl
  working.md
  long_term/
    profile.md
    facts.jsonl
    projects/
  meta/
    memory-system.md
    patches.jsonl
    retrieval-policy.md
  evals/
    cases.jsonl
    runs.jsonl
```

If the repo already has a memory convention, adapt to it instead of creating a parallel system. Keep raw events append-only.

## Script

Use the bundled shell script for deterministic file operations. It requires `jq`.

```bash
sh scripts/memory_ops.sh init --store .memory
sh scripts/memory_ops.sh event --store .memory --type feedback --text "User corrected X"
sh scripts/memory_ops.sh patch --store .memory --kind update_memory --target mem_123 --reason "User corrected stale fact" --after "..."
sh scripts/memory_ops.sh apply --store .memory --patch patch_...
sh scripts/memory_ops.sh eval-result --store .memory --case case_001 --before 0 --after 1 --notes "stale fact fixed"
```

The script intentionally does not infer correctness. It records structured evidence and applies explicit patches.

## Operating Rules

- Keep stable memories short and scoped.
- Store source evidence and confidence for every durable memory.
- Prefer clarifying questions for conflicting memories.
- Do not promote a one-off preference to long-term memory without explicit user wording or repeated evidence.
- Update `meta/memory-system.md` after significant failures or schema changes.
- Run or create eval cases before applying schema, retrieval, or skill patches.
- For skill patches, edit the relevant `SKILL.md` only after identifying the memory failure mode it fixes.

## Detailed References

- Read `references/schema.md` when creating memory items, patches, or storage migrations.
- Read `references/diagnostics.md` when deciding whether a problem is memory, retrieval, schema, or skill related.
- Read `references/evaluation.md` when setting up regression cases or scoring memory quality.
