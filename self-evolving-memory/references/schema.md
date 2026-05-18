# Memory Schema

Use these shapes as a baseline. Add fields only when they improve diagnosis, retrieval, or rollback.

## Memory Item

```json
{
  "id": "mem_20260518_abcdef",
  "type": "preference|fact|project|relationship|policy|procedure|meta",
  "scope": "global|project|room|task|skill",
  "content": "Short durable statement.",
  "status": "active|deprecated|superseded|candidate",
  "confidence": 0.8,
  "source": ["event_20260518_abcdef"],
  "created_at": "2026-05-18T00:00:00Z",
  "updated_at": "2026-05-18T00:00:00Z",
  "last_used_at": null,
  "last_validated_at": null,
  "decay": "none|slow|normal|fast",
  "tags": ["owner-preference"]
}
```

Rules:

- `content` should be concise and directly reusable.
- `source` points to event or message ids, never vague phrases like "conversation".
- `confidence < 0.6` should usually stay `candidate`.
- `decay: fast` is for volatile facts: schedules, prices, current status, room membership.

## Event

```json
{
  "id": "event_20260518_abcdef",
  "ts": "2026-05-18T00:00:00Z",
  "type": "observation|feedback|correction|tool_result|failure|patch|eval",
  "text": "What happened.",
  "source": "user|agent|tool|system",
  "refs": ["msg_id_or_file_path"],
  "tags": ["memory-failure"]
}
```

Events are append-only.

## Patch

```json
{
  "id": "patch_20260518_abcdef",
  "ts": "2026-05-18T00:00:00Z",
  "kind": "add_memory|update_memory|deprecate_memory|merge_memories|schema_patch|retrieval_policy_patch|skill_patch|eval_patch",
  "target": "mem_123_or_file_path",
  "failure_mode": "stale_memory",
  "reason": "Why this patch is needed.",
  "evidence": ["event_20260518_abcdef"],
  "before": "Existing content or summary.",
  "after": "New content or instruction.",
  "risk": "low|medium|high",
  "status": "proposed|applied|rejected|rolled_back",
  "applied_at": null,
  "result": null
}
```

Rules:

- Never apply `schema_patch`, `retrieval_policy_patch`, or `skill_patch` without a verification note.
- For `skill_patch`, `target` should be the relevant `SKILL.md` path and `after` should summarize the behavioral change, not contain a full file dump.
- For destructive changes, prefer `deprecate_memory` over deletion.

## Retrieval Policy Fields

Track retrieval behavior separately from memory content:

```json
{
  "scope": "project",
  "include_tags": ["project-context"],
  "exclude_status": ["deprecated"],
  "recency_weight": 0.2,
  "confidence_floor": 0.6,
  "max_items": 12,
  "conflict_behavior": "ask_user|prefer_newer|prefer_higher_confidence"
}
```

Use retrieval policy patches when the memory exists but the agent failed to use it.
