#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MEMORY_OPS="$SCRIPT_DIR/memory_ops.sh"

usage() {
  cat <<'EOF'
Usage:
  bash project_memory.sh root [--project PATH]
  bash project_memory.sh store [--project PATH]
  bash project_memory.sh init [--project PATH] [--mode shared|local]
  bash project_memory.sh context [--project PATH] [--limit N]
  bash project_memory.sh status [--project PATH]
  bash project_memory.sh merge --from STORE [--project PATH]
  bash project_memory.sh claim --memory ID --subject TEXT --predicate TEXT --value TEXT [--project PATH] [--qualifier TEXT] [--verifiability objective|subjective|preference|procedural] [--reason TEXT]
  bash project_memory.sh verify --memory ID --verdict verified|disputed|stale|unknown --evidence TEXT [--project PATH] [--ref REF] [--notes TEXT]
  bash project_memory.sh conflicts [--project PATH]
  bash project_memory.sh audit [--project PATH]
  bash project_memory.sh merge-items --into ID --from ID --after TEXT --reason TEXT [--project PATH]
  bash project_memory.sh forget --memory ID --reason TEXT [--project PATH] [--mode deprecate|suppress]
  bash project_memory.sh event|patch|apply|eval-result|list [memory_ops args...] [--project PATH]
EOF
}

now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

new_id() {
  prefix="$1"
  stamp="$(date -u +"%Y%m%d_%H%M%S")"
  if command -v uuidgen >/dev/null 2>&1; then
    suffix="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-8)"
  else
    suffix="$(date +%s)$$"
  fi
  printf "%s_%s_%s" "$prefix" "$stamp" "$suffix"
}

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "project_memory.sh requires jq" >&2
    exit 2
  fi
}

hash_line() {
  if command -v shasum >/dev/null 2>&1; then
    shasum | awk '{print $1}'
  elif command -v sha1sum >/dev/null 2>&1; then
    sha1sum | awk '{print $1}'
  else
    cksum | awk '{print $1 "-" $2}'
  fi
}

project_root() {
  project="$1"
  if git -C "$project" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$project" rev-parse --show-toplevel
  else
    (CDPATH= cd -- "$project" && pwd)
  fi
}

git_common_dir() {
  root="$1"
  common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 1
  case "$common" in
    /*) printf "%s\n" "$common" ;;
    *) printf "%s/%s\n" "$root" "$common" ;;
  esac
}

real_path() {
  path="$1"
  if [ -d "$path" ]; then
    (CDPATH= cd -- "$path" && pwd -P)
  elif [ -e "$path" ]; then
    dir="$(dirname -- "$path")"
    base="$(basename -- "$path")"
    printf "%s/%s\n" "$(CDPATH= cd -- "$dir" && pwd -P)" "$base"
  elif [ -L "$path" ] && command -v readlink >/dev/null 2>&1; then
    link="$(readlink "$path")"
    case "$link" in
      /*) printf "%s\n" "$link" ;;
      *) printf "%s/%s\n" "$(CDPATH= cd -- "$(dirname -- "$path")" && pwd -P)" "$link" ;;
    esac
  else
    printf "%s\n" "$path"
  fi
}

store_path() {
  root="$1"
  printf "%s/.memory\n" "$root"
}

parse_project_args() {
  PROJECT="."
  REST_ARGS=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project)
        PROJECT="$2"
        shift 2
        ;;
      *)
        REST_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

ensure_store() {
  store="$1"
  sh "$MEMORY_OPS" init --store "$store" >/dev/null
  [ -f "$store/meta/fact-verifications.jsonl" ] || : > "$store/meta/fact-verifications.jsonl"
}

ensure_project_store() {
  root="$1"
  store="$(store_path "$root")"
  if [ -e "$store" ] || [ -L "$store" ]; then
    ensure_store "$store"
  else
    cmd_init --project "$root" --mode shared >/dev/null
  fi
}

write_config() {
  store="$1"
  root="$2"
  mode="$3"
  mkdir -p "$store/meta"
  jq -n \
    --arg schema "1" \
    --arg project_root "$root" \
    --arg mode "$mode" \
    --arg updated_at "$(now)" \
    '{schema_version:$schema, project_root:$project_root, mode:$mode, updated_at:$updated_at}' \
    > "$store/meta/config.json"
}

append_jsonl() {
  path="$1"
  json="$2"
  mkdir -p "$(dirname "$path")"
  printf "%s\n" "$json" >> "$path"
}

latest_facts() {
  store="$1"
  [ -s "$store/long_term/facts.jsonl" ] || return 0
  jq -c -s '
    to_entries
    | map(.value + {__idx: .key})
    | group_by(.id // ("__missing_" + (.__idx | tostring)))
    | map(max_by(.__idx))
    | .[]
    | del(.__idx)
  ' "$store/long_term/facts.jsonl"
}

active_facts() {
  store="$1"
  latest_facts "$store" | jq -c '
    select((.status // "active") == "active")
    | select(((.tags // []) | index("suppress-retrieval")) | not)
  '
}

find_latest_memory() {
  store="$1"
  memory_id="$2"
  latest_facts "$store" | jq -c --arg id "$memory_id" 'select(.id == $id)' | tail -n 1
}

mark_patch_applied() {
  store="$1"
  patch_id="$2"
  result="$3"
  tmp="$store/meta/patches.jsonl.tmp"
  jq -c --arg id "$patch_id" --arg ts "$(now)" --arg result "$result" \
    'if .id == $id then .status = "applied" | .applied_at = $ts | .result = $result else . end' \
    "$store/meta/patches.jsonl" > "$tmp"
  mv "$tmp" "$store/meta/patches.jsonl"
}

json_array_from_lines() {
  printf "%s" "$1" | jq -R -s 'split("\n") | map(select(length > 0))'
}

cmd_root() {
  parse_project_args "$@"
  project_root "$PROJECT"
}

cmd_store() {
  parse_project_args "$@"
  root="$(project_root "$PROJECT")"
  store_path "$root"
}

cmd_init() {
  PROJECT="."
  MODE="shared"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) PROJECT="$2"; shift 2 ;;
      --mode) MODE="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done

  root="$(project_root "$PROJECT")"
  api_store="$(store_path "$root")"

  case "$MODE" in
    shared)
      if common="$(git_common_dir "$root")"; then
        real_store="$common/self-envolving-memory-project-scope/store"
        ensure_store "$real_store"
        if [ -e "$api_store" ] || [ -L "$api_store" ]; then
          current="$(real_path "$api_store")"
          expected="$(real_path "$real_store")"
          if [ "$current" != "$expected" ]; then
            echo "refusing to replace existing .memory: $api_store" >&2
            echo "merge it first: bash scripts/project_memory.sh merge --from $api_store --project $root" >&2
            exit 1
          fi
        else
          ln -s "$real_store" "$api_store"
        fi
        write_config "$real_store" "$root" "$MODE"
        jq -n --arg root "$root" --arg store "$api_store" --arg real_store "$real_store" --arg mode "$MODE" \
          '{root:$root, store:$store, real_store:$real_store, mode:$mode, initialized:true}'
      else
        ensure_store "$api_store"
        write_config "$api_store" "$root" "local"
        jq -n --arg root "$root" --arg store "$api_store" '{root:$root, store:$store, mode:"local", initialized:true, note:"not a git repository"}'
      fi
      ;;
    local)
      ensure_store "$api_store"
      write_config "$api_store" "$root" "$MODE"
      jq -n --arg root "$root" --arg store "$api_store" --arg mode "$MODE" \
        '{root:$root, store:$store, mode:$mode, initialized:true}'
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

cmd_context() {
  PROJECT="."
  LIMIT="20"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) PROJECT="$2"; shift 2 ;;
      --limit) LIMIT="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  ensure_project_store "$root"

  printf "# Project Memory Context\n\n"
  printf '%s\n' "- project: $root"
  printf '%s\n\n' "- store: $store"

  if [ -s "$store/working.md" ]; then
    printf "## Working\n\n"
    sed -n '1,160p' "$store/working.md"
    printf "\n\n"
  fi

  if [ -s "$store/long_term/profile.md" ]; then
    printf "## Profile\n\n"
    sed -n '1,160p' "$store/long_term/profile.md"
    printf "\n\n"
  fi

  printf "## Active Memories\n\n"
  if [ -s "$store/long_term/facts.jsonl" ]; then
    latest_facts "$store" | jq -r --argjson limit "$LIMIT" -s '
      map(
        select((.status // "active") == "active")
        | select(((.tags // []) | index("suppress-retrieval")) | not)
        | select((.confidence // 0) >= 0.6)
      )
      | .[-$limit:][]
      | "- [" + (.id // "unknown") + "] "
        + (.content // "")
        + " (type=" + (.type // "fact")
        + ", scope=" + (.scope // "project")
        + ", confidence=" + ((.confidence // 0) | tostring) + ")"
    '
  else
    printf "No active memories.\n"
  fi
  printf "\n\n"

  if [ -s "$store/meta/retrieval-policy.md" ]; then
    printf "## Retrieval Policy\n\n"
    sed -n '1,120p' "$store/meta/retrieval-policy.md"
    printf "\n"
  fi
}

cmd_status() {
  parse_project_args "$@"
  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  store_real="$(real_path "$store")"

  jq -n --arg root "$root" --arg store "$store" --arg real_store "$store_real" \
    '{root:$root, store:$store, real_store:$real_store}'

  if git -C "$root" worktree list --porcelain >/dev/null 2>&1; then
    git -C "$root" worktree list --porcelain | awk '
      /^worktree / { if (path != "") print path; path=substr($0, 10) }
      END { if (path != "") print path }
    ' | while IFS= read -r wt; do
      wt_store="$wt/.memory"
      if [ -e "$wt_store" ] || [ -L "$wt_store" ]; then
        wt_real="$(real_path "$wt_store")"
        if [ "$wt_real" = "$store_real" ]; then
          state="shared"
        else
          state="forked"
        fi
      else
        wt_real=""
        state="missing"
      fi
      jq -n --arg worktree "$wt" --arg store "$wt_store" --arg real_store "$wt_real" --arg state "$state" \
        '{worktree:$worktree, store:$store, real_store:$real_store, state:$state}'
    done
  fi
}

record_conflict() {
  store="$1"
  name="$2"
  ours="$3"
  theirs="$4"
  conflict_dir="$store/meta/conflicts"
  mkdir -p "$conflict_dir"
  id="$(new_id conflict)"
  printf "%s\n" "$ours" > "$conflict_dir/${id}.${name}.ours"
  printf "%s\n" "$theirs" > "$conflict_dir/${id}.${name}.theirs"
  printf "%s\n" "$id"
}

merge_jsonl() {
  store="$1"
  src="$2"
  rel="$3"
  dst="$store/$rel"
  [ -f "$src/$rel" ] || return 0
  mkdir -p "$(dirname "$dst")"
  [ -f "$dst" ] || : > "$dst"

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    key="$(printf "%s\n" "$line" | jq -r '.id // empty')"
    [ -n "$key" ] || key="$(printf "%s\n" "$line" | hash_line)"
    existing="$(jq -c --arg id "$key" 'select((.id // "") == $id)' "$dst" 2>/dev/null | head -n 1 || true)"
    if [ -z "$existing" ]; then
      printf "%s\n" "$line" >> "$dst"
      MERGED_COUNT=$((MERGED_COUNT + 1))
    else
      existing_canon="$(printf "%s\n" "$existing" | jq -cS .)"
      incoming_canon="$(printf "%s\n" "$line" | jq -cS .)"
      if [ "$existing_canon" != "$incoming_canon" ]; then
        record_conflict "$store" "$(printf "%s" "$rel" | tr '/.' '__')" "$existing" "$line" >/dev/null
        CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
      fi
    fi
  done < "$src/$rel"
}

merge_markdown() {
  store="$1"
  src="$2"
  rel="$3"
  dst="$store/$rel"
  [ -f "$src/$rel" ] || return 0
  mkdir -p "$(dirname "$dst")"
  if [ ! -f "$dst" ]; then
    cp "$src/$rel" "$dst"
    MERGED_COUNT=$((MERGED_COUNT + 1))
    return 0
  fi
  if cmp -s "$src/$rel" "$dst"; then
    return 0
  fi
  theirs="$(sed -n '1,240p' "$src/$rel")"
  ours="$(sed -n '1,240p' "$dst")"
  record_conflict "$store" "$(printf "%s" "$rel" | tr '/.' '__')" "$ours" "$theirs" >/dev/null
  CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
}

cmd_merge() {
  PROJECT="."
  FROM=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) PROJECT="$2"; shift 2 ;;
      --from) FROM="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [ -n "$FROM" ] || { usage; exit 2; }
  [ -d "$FROM" ] || { echo "source store not found: $FROM" >&2; exit 1; }

  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  ensure_project_store "$root"

  MERGED_COUNT=0
  CONFLICT_COUNT=0
  merge_jsonl "$store" "$FROM" "events.jsonl"
  merge_jsonl "$store" "$FROM" "long_term/facts.jsonl"
  merge_jsonl "$store" "$FROM" "meta/patches.jsonl"
  merge_jsonl "$store" "$FROM" "evals/cases.jsonl"
  merge_jsonl "$store" "$FROM" "evals/runs.jsonl"

  merge_markdown "$store" "$FROM" "working.md"
  merge_markdown "$store" "$FROM" "long_term/profile.md"
  merge_markdown "$store" "$FROM" "meta/memory-system.md"
  merge_markdown "$store" "$FROM" "meta/retrieval-policy.md"

  event_text="Merged project memory from $FROM into $store; records=$MERGED_COUNT conflicts=$CONFLICT_COUNT"
  sh "$MEMORY_OPS" event --store "$store" --type observation --source agent --tag memory-merge --text "$event_text" >/dev/null

  jq -n --arg store "$store" --arg from "$FROM" --argjson records "$MERGED_COUNT" --argjson conflicts "$CONFLICT_COUNT" \
    '{store:$store, from:$from, merged_records:$records, conflicts:$conflicts}'
}

conflicts_report() {
  store="$1"
  active_facts "$store" | jq -s '
    map(
      select(.claim != null)
      | select((.claim.verifiability // "objective") == "objective")
      | select(.claim.subject != null and .claim.predicate != null and .claim.value != null)
    )
    | sort_by(.claim.subject, .claim.predicate, (.claim.qualifier // ""))
    | group_by([.claim.subject, .claim.predicate, (.claim.qualifier // "")])
    | map(
      select((map(.claim.value | tostring) | unique | length) > 1)
      | {
          key: {
            subject: .[0].claim.subject,
            predicate: .[0].claim.predicate,
            qualifier: (.[0].claim.qualifier // "")
          },
          values: (
            sort_by(.claim.value | tostring)
            | group_by(.claim.value | tostring)
            | map({
                value: .[0].claim.value,
                memories: map({
                  id: .id,
                  content: .content,
                  confidence: (.confidence // null),
                  last_validated_at: (.last_validated_at // null),
                  verification: (.verification // null)
                })
              })
          )
        }
    )
    | {count: length, conflicts: .}
  '
}

cmd_claim() {
  PROJECT="."
  MEMORY_ID=""
  SUBJECT=""
  PREDICATE=""
  VALUE=""
  QUALIFIER=""
  VERIFIABILITY="objective"
  REASON="Annotate memory as a structured claim for fact validation and conflict detection."
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) PROJECT="$2"; shift 2 ;;
      --memory) MEMORY_ID="$2"; shift 2 ;;
      --subject) SUBJECT="$2"; shift 2 ;;
      --predicate) PREDICATE="$2"; shift 2 ;;
      --value) VALUE="$2"; shift 2 ;;
      --qualifier) QUALIFIER="$2"; shift 2 ;;
      --verifiability) VERIFIABILITY="$2"; shift 2 ;;
      --reason) REASON="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [ -n "$MEMORY_ID" ] && [ -n "$SUBJECT" ] && [ -n "$PREDICATE" ] && [ -n "$VALUE" ] || { usage; exit 2; }
  case "$VERIFIABILITY" in objective|subjective|preference|procedural) ;; *) usage; exit 2 ;; esac

  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  ensure_project_store "$root"
  memory="$(find_latest_memory "$store" "$MEMORY_ID")"
  [ -n "$memory" ] || { echo "memory not found: $MEMORY_ID" >&2; exit 1; }

  claim="$(jq -n \
    --arg subject "$SUBJECT" --arg predicate "$PREDICATE" --arg value "$VALUE" \
    --arg qualifier "$QUALIFIER" --arg verifiability "$VERIFIABILITY" \
    '{subject:$subject, predicate:$predicate, value:$value, qualifier:$qualifier, verifiability:$verifiability}')"
  event="$(sh "$MEMORY_OPS" event --store "$store" --type observation --source agent --tag memory-claim --text "Annotated memory $MEMORY_ID as claim $SUBJECT / $PREDICATE.")"
  event_id="$(printf "%s" "$event" | jq -r .id)"
  before="$(printf "%s" "$memory" | jq -c '.claim // null')"
  after="$(printf "%s" "$claim" | jq -c .)"
  patch="$(sh "$MEMORY_OPS" patch --store "$store" --kind update_memory --target "$MEMORY_ID" \
    --failure-mode bad_schema --reason "$REASON" --evidence "$event_id" --before "$before" --after "$after")"
  patch_id="$(printf "%s" "$patch" | jq -r .id)"

  updated="$(printf "%s" "$memory" | jq -c \
    --argjson claim "$claim" --arg ts "$(now)" --arg event "$event_id" --arg verifiability "$VERIFIABILITY" '
      .claim = $claim
      | .updated_at = $ts
      | .source = (((.source // []) + [$event]) | unique)
      | .tags = (((.tags // []) + (if $verifiability == "objective" then ["objective-fact"] else [] end)) | unique)
      | .verification = ((.verification // {}) + {status:"unverified", checked_at:null, evidence:[], refs:[], notes:null})
    ')"
  append_jsonl "$store/long_term/facts.jsonl" "$updated"
  mark_patch_applied "$store" "$patch_id" "claim annotated"

  jq -n --argjson event "$event" --argjson patch "$patch" --argjson memory "$updated" \
    '{event:$event, patch:$patch, memory:$memory}'
}

cmd_verify() {
  PROJECT="."
  MEMORY_ID=""
  VERDICT=""
  EVIDENCE=""
  REFS=""
  NOTES=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) PROJECT="$2"; shift 2 ;;
      --memory) MEMORY_ID="$2"; shift 2 ;;
      --verdict) VERDICT="$2"; shift 2 ;;
      --evidence) EVIDENCE="$2"; shift 2 ;;
      --ref) REFS="${REFS}$2
"; shift 2 ;;
      --notes) NOTES="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [ -n "$MEMORY_ID" ] && [ -n "$VERDICT" ] && [ -n "$EVIDENCE" ] || { usage; exit 2; }
  case "$VERDICT" in verified|disputed|stale|unknown) ;; *) usage; exit 2 ;; esac

  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  ensure_project_store "$root"
  memory="$(find_latest_memory "$store" "$MEMORY_ID")"
  [ -n "$memory" ] || { echo "memory not found: $MEMORY_ID" >&2; exit 1; }

  event="$(sh "$MEMORY_OPS" event --store "$store" --type tool_result --source agent --tag fact-verification --text "Verification for $MEMORY_ID: $VERDICT. $EVIDENCE")"
  event_id="$(printf "%s" "$event" | jq -r .id)"
  verification_id="$(new_id verification)"
  refs_json="$(json_array_from_lines "$REFS")"
  verification="$(jq -n \
    --arg id "$verification_id" --arg ts "$(now)" --arg memory "$MEMORY_ID" \
    --arg verdict "$VERDICT" --arg evidence "$EVIDENCE" --arg event "$event_id" \
    --arg notes "$NOTES" --argjson refs "$refs_json" \
    '{id:$id, ts:$ts, memory_id:$memory, verdict:$verdict, evidence:$evidence, refs:$refs, notes:$notes, event:$event}')"
  append_jsonl "$store/meta/fact-verifications.jsonl" "$(printf "%s" "$verification" | jq -c .)"

  patch="$(sh "$MEMORY_OPS" patch --store "$store" --kind update_memory --target "$MEMORY_ID" \
    --failure-mode stale_memory --reason "Record objective fact verification result." \
    --evidence "$event_id" --before "$(printf "%s" "$memory" | jq -c '.verification // null')" \
    --after "$(printf "%s" "$verification" | jq -c .)")"
  patch_id="$(printf "%s" "$patch" | jq -r .id)"

  updated="$(printf "%s" "$memory" | jq -c \
    --arg ts "$(now)" --arg event "$event_id" --arg verification_id "$verification_id" \
    --arg verdict "$VERDICT" --arg evidence "$EVIDENCE" --arg notes "$NOTES" --argjson refs "$refs_json" '
      .updated_at = $ts
      | .last_validated_at = $ts
      | .source = (((.source // []) + [$event]) | unique)
      | .verification = {
          status: $verdict,
          checked_at: $ts,
          evidence: [$verification_id],
          refs: $refs,
          notes: $notes
        }
      | if $verdict == "verified" then
          .confidence = (if (.confidence // 0) < 0.8 then 0.8 else .confidence end)
          | .tags = (((.tags // []) + ["fact-verified"]) | unique)
        elif $verdict == "disputed" then
          .status = "candidate"
          | .tags = (((.tags // []) + ["disputed"]) | unique)
        elif $verdict == "stale" then
          .status = "candidate"
          | .decay = "fast"
          | .tags = (((.tags // []) + ["stale", "needs-update"]) | unique)
        else
          .tags = (((.tags // []) + ["verification-unknown"]) | unique)
        end
    ')"
  append_jsonl "$store/long_term/facts.jsonl" "$updated"
  mark_patch_applied "$store" "$patch_id" "verification recorded"

  jq -n --argjson event "$event" --argjson patch "$patch" --argjson verification "$verification" --argjson memory "$updated" \
    '{event:$event, patch:$patch, verification:$verification, memory:$memory}'
}

cmd_conflicts() {
  parse_project_args "$@"
  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  ensure_project_store "$root"
  conflicts_report "$store"
}

cmd_audit() {
  parse_project_args "$@"
  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  ensure_project_store "$root"
  facts_json="$(active_facts "$store" | jq -s '.')"
  conflicts_json="$(conflicts_report "$store")"
  jq -n --arg root "$root" --arg store "$store" --argjson facts "$facts_json" --argjson conflicts "$conflicts_json" '
    {
      root: $root,
      store: $store,
      objective_validation_required: (
        $facts
        | map(select(
            (((.claim.verifiability // "") == "objective") or ((.tags // []) | index("objective-fact")))
            and (((.verification.status // "unverified") == "unverified") or ((.verification.status // "unverified") == "unknown"))
          )
          | {id, content, claim, verification: (.verification // null), reason:"objective_fact_unverified"})
      ),
      weak_or_missing_evidence: (
        $facts
        | map(select(((.source // []) | length) == 0 or ((.confidence // 0) < 0.6))
          | {id, content, confidence: (.confidence // null), source: (.source // []), reason:"weak_or_missing_evidence"})
      ),
      conflicts: $conflicts.conflicts,
      forget_candidates: (
        $facts
        | map(select(
            ((.tags // []) | index("forget-candidate"))
            or ((.tags // []) | index("ephemeral"))
            or (((.decay // "") == "fast") and ((.last_validated_at // "") == ""))
            or ((.verification.status // "") == "unknown")
          )
          | {id, content, decay: (.decay // null), tags: (.tags // []), verification: (.verification // null), reason:"candidate_for_selective_forgetting_or_review"})
      )
    }
  '
}

cmd_merge_items() {
  PROJECT="."
  INTO_ID=""
  FROM_ID=""
  AFTER=""
  REASON=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) PROJECT="$2"; shift 2 ;;
      --into) INTO_ID="$2"; shift 2 ;;
      --from) FROM_ID="$2"; shift 2 ;;
      --after) AFTER="$2"; shift 2 ;;
      --reason) REASON="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [ -n "$INTO_ID" ] && [ -n "$FROM_ID" ] && [ -n "$AFTER" ] && [ -n "$REASON" ] || { usage; exit 2; }

  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  ensure_project_store "$root"
  into_memory="$(find_latest_memory "$store" "$INTO_ID")"
  from_memory="$(find_latest_memory "$store" "$FROM_ID")"
  [ -n "$into_memory" ] || { echo "memory not found: $INTO_ID" >&2; exit 1; }
  [ -n "$from_memory" ] || { echo "memory not found: $FROM_ID" >&2; exit 1; }

  before="$(jq -n --argjson into "$into_memory" --argjson from "$from_memory" '{into:$into, from:$from}' | jq -c .)"
  event="$(sh "$MEMORY_OPS" event --store "$store" --type observation --source agent --tag memory-item-merge --text "Merged memory $FROM_ID into $INTO_ID. $REASON")"
  event_id="$(printf "%s" "$event" | jq -r .id)"
  patch="$(sh "$MEMORY_OPS" patch --store "$store" --kind merge_memories --target "$INTO_ID" \
    --failure-mode conflicting_memory --reason "$REASON" --evidence "$event_id" --before "$before" --after "$AFTER")"
  patch_id="$(printf "%s" "$patch" | jq -r .id)"
  from_source="$(printf "%s" "$from_memory" | jq -c '.source // []')"

  updated_into="$(printf "%s" "$into_memory" | jq -c \
    --arg content "$AFTER" --arg ts "$(now)" --arg event "$event_id" --arg from "$FROM_ID" --argjson from_source "$from_source" '
      .content = $content
      | .status = "active"
      | .updated_at = $ts
      | .source = (((.source // []) + $from_source + [$event]) | unique)
      | .tags = (((.tags // []) + ["merged-memory"]) | unique)
      | .merged_from = (((.merged_from // []) + [$from]) | unique)
    ')"
  deprecated_from="$(printf "%s" "$from_memory" | jq -c \
    --arg ts "$(now)" --arg event "$event_id" --arg into "$INTO_ID" '
      .status = "deprecated"
      | .updated_at = $ts
      | .source = (((.source // []) + [$event]) | unique)
      | .tags = (((.tags // []) + ["merged-memory"]) | unique)
      | .superseded_by = $into
    ')"
  append_jsonl "$store/long_term/facts.jsonl" "$updated_into"
  append_jsonl "$store/long_term/facts.jsonl" "$deprecated_from"
  mark_patch_applied "$store" "$patch_id" "memory items merged"

  jq -n --argjson event "$event" --argjson patch "$patch" --argjson into "$updated_into" --argjson from "$deprecated_from" \
    '{event:$event, patch:$patch, merged_into:$into, deprecated:$from}'
}

cmd_forget() {
  PROJECT="."
  MEMORY_ID=""
  REASON=""
  MODE="deprecate"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) PROJECT="$2"; shift 2 ;;
      --memory) MEMORY_ID="$2"; shift 2 ;;
      --reason) REASON="$2"; shift 2 ;;
      --mode) MODE="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [ -n "$MEMORY_ID" ] && [ -n "$REASON" ] || { usage; exit 2; }
  case "$MODE" in deprecate|suppress) ;; *) usage; exit 2 ;; esac

  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  ensure_project_store "$root"
  memory="$(find_latest_memory "$store" "$MEMORY_ID")"
  [ -n "$memory" ] || { echo "memory not found: $MEMORY_ID" >&2; exit 1; }

  event="$(sh "$MEMORY_OPS" event --store "$store" --type correction --source agent --tag selective-forgetting --text "Selective forgetting for $MEMORY_ID with mode $MODE. $REASON")"
  event_id="$(printf "%s" "$event" | jq -r .id)"
  if [ "$MODE" = "deprecate" ]; then
    patch_kind="deprecate_memory"
    after="$(printf "%s" "$memory" | jq -r '.content // ""')"
  else
    patch_kind="update_memory"
    after="Suppress from retrieval: $REASON"
  fi
  patch="$(sh "$MEMORY_OPS" patch --store "$store" --kind "$patch_kind" --target "$MEMORY_ID" \
    --failure-mode overgeneralized_memory --reason "$REASON" --evidence "$event_id" \
    --before "$(printf "%s" "$memory" | jq -c .)" --after "$after")"
  patch_id="$(printf "%s" "$patch" | jq -r .id)"

  updated="$(printf "%s" "$memory" | jq -c \
    --arg ts "$(now)" --arg event "$event_id" --arg mode "$MODE" --arg reason "$REASON" '
      .updated_at = $ts
      | .source = (((.source // []) + [$event]) | unique)
      | .forget = {mode:$mode, reason:$reason, at:$ts, event:$event}
      | .tags = (((.tags // []) + ["forgotten"] + (if $mode == "suppress" then ["suppress-retrieval"] else [] end)) | unique)
      | if $mode == "deprecate" then .status = "deprecated" else . end
    ')"
  append_jsonl "$store/long_term/facts.jsonl" "$updated"
  mark_patch_applied "$store" "$patch_id" "selective forgetting applied"

  jq -n --argjson event "$event" --argjson patch "$patch" --argjson memory "$updated" \
    '{event:$event, patch:$patch, memory:$memory}'
}

cmd_delegate() {
  subcmd="$1"
  shift
  parse_project_args "$@"
  root="$(project_root "$PROJECT")"
  store="$(store_path "$root")"
  ensure_project_store "$root"
  sh "$MEMORY_OPS" "$subcmd" --store "$store" "${REST_ARGS[@]}"
}

need_jq
[ "$#" -gt 0 ] || { usage; exit 2; }
cmd="$1"
shift

case "$cmd" in
  root) cmd_root "$@" ;;
  store) cmd_store "$@" ;;
  init) cmd_init "$@" ;;
  context) cmd_context "$@" ;;
  status) cmd_status "$@" ;;
  merge) cmd_merge "$@" ;;
  claim) cmd_claim "$@" ;;
  verify) cmd_verify "$@" ;;
  conflicts) cmd_conflicts "$@" ;;
  audit) cmd_audit "$@" ;;
  merge-items) cmd_merge_items "$@" ;;
  forget) cmd_forget "$@" ;;
  event|patch|apply|eval-result|list) cmd_delegate "$cmd" "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
