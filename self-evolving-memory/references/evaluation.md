# Memory Evaluation

Use evals to prevent "self-improvement" from becoming uncontrolled memory churn.

## Case Shape

```json
{
  "id": "case_001",
  "name": "Uses confirmed forwarding room",
  "prompt": "Where should Garry monitor notifications be sent?",
  "expected": "rm_oc_551556d402d68263",
  "checks": ["mentions_confirmed_room", "does_not_call_it_candidate"],
  "tags": ["retrieval", "owner-preference"]
}
```

Store cases in `.memory/evals/cases.jsonl`.

## Scoring

Use a simple 0/1 score unless a richer rubric is necessary.

Common checks:

- `recall`: did the agent retrieve the needed memory?
- `precision`: did the agent avoid irrelevant memory?
- `freshness`: did it avoid stale facts?
- `conflict_handling`: did it ask or scope conflicts correctly?
- `evidence`: did it cite or preserve provenance when updating memory?
- `behavior`: did the skill/output change actually solve the original failure?

## Minimum Verification by Patch Type

- `add_memory`: no eval required if user explicitly requested "remember this"; record evidence.
- `update_memory`: verify the old content will no longer be used.
- `deprecate_memory`: verify at least one replacement or reason exists.
- `retrieval_policy_patch`: run a case where the memory previously existed but was not used.
- `schema_patch`: run migration dry-run or inspect a sample converted item.
- `skill_patch`: test one prompt that previously failed and one unrelated prompt to avoid trigger overreach.

## Eval Result Shape

```json
{
  "id": "run_20260518_abcdef",
  "case": "case_001",
  "patch": "patch_20260518_abcdef",
  "before": 0,
  "after": 1,
  "notes": "Confirmed target room is no longer described as candidate.",
  "ts": "2026-05-18T00:00:00Z"
}
```

Store results in `.memory/evals/runs.jsonl`.
