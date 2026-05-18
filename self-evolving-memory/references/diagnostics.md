# Memory Diagnostics

Use this guide after user feedback, failed task completion, or surprising behavior.

## Decision Tree

1. Did the needed information exist in memory?
   - No: `missing_memory`
   - Yes: continue.
2. Was the stored information false?
   - Yes: `wrong_memory`
3. Was it true before but outdated now?
   - Yes: `stale_memory`
4. Was a narrow example turned into a broad rule?
   - Yes: `overgeneralized_memory`
5. Did memory contain conflicting information?
   - Yes: `conflicting_memory`
6. Was the right memory present but not used?
   - Yes: `underused_memory` or `bad_retrieval`
7. Could the memory not be represented cleanly?
   - Yes: `bad_schema`
8. Did a skill workflow cause wrong capture, wrong use, or wrong output?
   - Yes: `bad_skill`

## Failure Modes

### missing_memory

Signal: user says "I already told you", "remember this", or repeats stable context.

Patch: `add_memory`, usually with `status: active` only if evidence is explicit.

### wrong_memory

Signal: memory contradicts user correction or source of truth.

Patch: `update_memory` if the same item is still useful; otherwise `deprecate_memory` plus `add_memory`.

### stale_memory

Signal: current status changed: roles, room ids, dates, schedules, product versions, prices.

Patch: `update_memory`, set `decay` appropriately, and add `last_validated_at`.

### overgeneralized_memory

Signal: agent applies a preference too broadly.

Patch: narrow `scope`, lower confidence, or rewrite content with explicit exceptions.

### underused_memory

Signal: correct memory exists but response ignored it.

Patch: `retrieval_policy_patch` or `skill_patch`; update `last_used_at` only after successful use.

### conflicting_memory

Signal: two active memories disagree.

Patch: ask the user if the conflict affects behavior. If not possible, preserve both with scope/time metadata and avoid decisive action.

### bad_schema

Signal: repeated awkward free-text notes, missing provenance, no way to rank trust, no way to expire volatile facts.

Patch: `schema_patch` and migration notes.

### bad_skill

Signal: a skill repeatedly writes noisy memories, fails to read memory, or promotes unverified assumptions.

Patch: update the skill trigger/workflow. Add guardrails such as "classify feedback before writing memory" or "ask before promoting candidate memories".

## Promotion Rules

Promote a candidate to long-term memory only when one is true:

- The user explicitly says to remember it.
- The same preference/fact appears in repeated interactions.
- It is a stable identity, project, room, tool, or policy fact needed for future tasks.
- Losing it would likely cause repeated user friction.

Keep as working memory when:

- It is only relevant to the current task.
- It is a tentative hypothesis.
- The user has not confirmed the inference.

Avoid storing:

- Sensitive secrets unless the system has an explicit secure store.
- One-off phrasing preferences with weak evidence.
- Current facts that require live verification unless marked volatile.
