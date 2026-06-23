# Memory Quality Operations

Use these operations to keep project memory reliable without making the agent silently rewrite history.

## Objective Fact Verification

An objective fact should have a structured `claim` when it needs validation or conflict checks:

```json
{
  "claim": {
    "subject": "deploy.preview",
    "predicate": "target",
    "value": "staging",
    "qualifier": "",
    "verifiability": "objective"
  },
  "verification": {
    "status": "unverified|verified|disputed|stale|unknown",
    "checked_at": "2026-06-23T00:00:00Z",
    "evidence": ["verification_..."],
    "refs": ["deploy.yaml"],
    "notes": ""
  }
}
```

Use `claim` to add this structure to an existing memory. Use `verify` only after checking the source of truth, such as repo files, tool output, user correction, or an official source.

Verdict behavior:

- `verified`: keep active and raise confidence to at least `0.8`.
- `disputed`: change latest version to `candidate` so it is not retrieved as active memory.
- `stale`: change latest version to `candidate`, set `decay: fast`, and tag `needs-update`.
- `unknown`: keep status but tag `verification-unknown`.

## Conflict Detection

`conflicts` compares active objective claims with the same:

```text
claim.subject + claim.predicate + claim.qualifier
```

Different `claim.value` values under the same key are reported as a contradiction candidate. Free-text memories are not guessed as contradictions; annotate them with `claim` first.

## Item Merge

Use `merge-items` after deciding the surviving statement. It appends:

- an applied `merge_memories` patch,
- a new active version of the `--into` memory with the merged content,
- a deprecated version of the `--from` memory with `superseded_by`.

Do not merge unresolved conflicts. If the source of truth is unclear, ask the user or mark the disputed memories with `verify --verdict disputed`.

## Selective Forgetting

Use `forget` for reversible forgetting:

- `--mode deprecate`: latest version becomes `deprecated`.
- `--mode suppress`: latest version stays active but is tagged `suppress-retrieval`.

Both modes preserve evidence and patch history. They are appropriate for stale, over-broad, low-value, or no-longer-relevant memory. They are not suitable for secure deletion of secrets from append-only logs.

Use `audit` to find likely candidates:

- objective facts still unverified,
- active memories with weak evidence,
- structured claim contradictions,
- fast-decay or explicitly ephemeral memories that were not validated.
