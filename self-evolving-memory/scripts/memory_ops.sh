#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  memory_ops.sh init [--store .memory]
  memory_ops.sh event --type TYPE --text TEXT [--store .memory] [--source SOURCE] [--id ID] [--ref REF] [--tag TAG]
  memory_ops.sh patch --kind KIND --reason REASON --after TEXT [--store .memory] [--id ID] [--target ID] [--failure-mode MODE] [--evidence ID] [--before TEXT] [--risk low|medium|high]
  memory_ops.sh apply --patch PATCH_ID [--store .memory] [--result TEXT] [--memory-type TYPE] [--scope SCOPE] [--confidence N] [--decay MODE] [--tag TAG] [--validated]
  memory_ops.sh eval-result --case CASE_ID --before N --after N [--store .memory] [--id ID] [--patch PATCH_ID] [--notes TEXT]
  memory_ops.sh list events|patches|facts|evals [--store .memory] [--limit N]
EOF
}

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "memory_ops.sh requires jq" >&2
    exit 2
  fi
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

lines_json() {
  printf "%s" "$1" | jq -R -s 'split("\n") | map(select(length > 0))'
}

append_jsonl() {
  path="$1"
  json="$2"
  mkdir -p "$(dirname "$path")"
  printf "%s\n" "$json" >> "$path"
}

touch_store() {
  store="$1"
  mkdir -p "$store/long_term/projects" "$store/meta" "$store/evals"
  [ -f "$store/events.jsonl" ] || : > "$store/events.jsonl"
  [ -f "$store/long_term/facts.jsonl" ] || : > "$store/long_term/facts.jsonl"
  [ -f "$store/meta/patches.jsonl" ] || : > "$store/meta/patches.jsonl"
  [ -f "$store/evals/cases.jsonl" ] || : > "$store/evals/cases.jsonl"
  [ -f "$store/evals/runs.jsonl" ] || : > "$store/evals/runs.jsonl"
  [ -f "$store/working.md" ] || printf "# Working Memory\n" > "$store/working.md"
  [ -f "$store/long_term/profile.md" ] || printf "# Long-Term Profile\n" > "$store/long_term/profile.md"
  [ -f "$store/meta/memory-system.md" ] || printf "# Memory System Notes\n" > "$store/meta/memory-system.md"
  if [ ! -f "$store/meta/retrieval-policy.md" ]; then
    cat > "$store/meta/retrieval-policy.md" <<'EOF'
# Retrieval Policy

- Exclude deprecated memories.
- Prefer higher confidence and more specific scope.
- Ask on unresolved conflicts.
EOF
  fi
}

parse_common_store() {
  STORE=".memory"
}

cmd_init() {
  parse_common_store
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --store) STORE="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  touch_store "$STORE"
  jq -n --arg store "$STORE" '{store:$store, initialized:true}'
}

cmd_event() {
  parse_common_store
  ID=""
  TYPE=""
  TEXT=""
  SOURCE="agent"
  REFS=""
  TAGS=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --store) STORE="$2"; shift 2 ;;
      --id) ID="$2"; shift 2 ;;
      --type) TYPE="$2"; shift 2 ;;
      --text) TEXT="$2"; shift 2 ;;
      --source) SOURCE="$2"; shift 2 ;;
      --ref) REFS="${REFS}$2
"; shift 2 ;;
      --tag) TAGS="${TAGS}$2
"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [ -n "$TYPE" ] && [ -n "$TEXT" ] || { usage; exit 2; }
  [ -n "$ID" ] || ID="$(new_id event)"
  json="$(jq -n \
    --arg id "$ID" --arg ts "$(now)" --arg type "$TYPE" --arg text "$TEXT" --arg source "$SOURCE" \
    --argjson refs "$(lines_json "$REFS")" --argjson tags "$(lines_json "$TAGS")" \
    '{id:$id, ts:$ts, type:$type, text:$text, source:$source, refs:$refs, tags:$tags}')"
  append_jsonl "$STORE/events.jsonl" "$(printf "%s" "$json" | jq -c .)"
  printf "%s\n" "$json"
}

cmd_patch() {
  parse_common_store
  ID=""
  KIND=""
  TARGET=""
  FAILURE_MODE=""
  REASON=""
  EVIDENCE=""
  BEFORE=""
  AFTER=""
  RISK="low"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --store) STORE="$2"; shift 2 ;;
      --id) ID="$2"; shift 2 ;;
      --kind) KIND="$2"; shift 2 ;;
      --target) TARGET="$2"; shift 2 ;;
      --failure-mode) FAILURE_MODE="$2"; shift 2 ;;
      --reason) REASON="$2"; shift 2 ;;
      --evidence) EVIDENCE="${EVIDENCE}$2
"; shift 2 ;;
      --before) BEFORE="$2"; shift 2 ;;
      --after) AFTER="$2"; shift 2 ;;
      --risk) RISK="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [ -n "$KIND" ] && [ -n "$REASON" ] && [ -n "$AFTER" ] || { usage; exit 2; }
  [ -n "$ID" ] || ID="$(new_id patch)"
  json="$(jq -n \
    --arg id "$ID" --arg ts "$(now)" --arg kind "$KIND" --arg target "$TARGET" \
    --arg failure_mode "$FAILURE_MODE" --arg reason "$REASON" --arg before "$BEFORE" --arg after "$AFTER" --arg risk "$RISK" \
    --argjson evidence "$(lines_json "$EVIDENCE")" \
    '{id:$id, ts:$ts, kind:$kind, target:$target, failure_mode:$failure_mode, reason:$reason, evidence:$evidence, before:$before, after:$after, risk:$risk, status:"proposed", applied_at:null, result:null}')"
  append_jsonl "$STORE/meta/patches.jsonl" "$(printf "%s" "$json" | jq -c .)"
  printf "%s\n" "$json"
}

find_patch() {
  store="$1"
  patch_id="$2"
  [ -f "$store/meta/patches.jsonl" ] || return 1
  jq -c --arg id "$patch_id" 'select(.id == $id)' "$store/meta/patches.jsonl" | tail -n 1
}

rewrite_patch() {
  store="$1"
  patch_id="$2"
  updated="$3"
  tmp="$store/meta/patches.jsonl.tmp"
  jq -c --arg id "$patch_id" --argjson updated "$updated" 'if .id == $id then $updated else . end' "$store/meta/patches.jsonl" > "$tmp"
  mv "$tmp" "$store/meta/patches.jsonl"
}

cmd_apply() {
  parse_common_store
  PATCH_ID=""
  RESULT=""
  MEMORY_TYPE="fact"
  SCOPE="global"
  CONFIDENCE="0.8"
  DECAY="normal"
  TAGS=""
  VALIDATED="false"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --store) STORE="$2"; shift 2 ;;
      --patch) PATCH_ID="$2"; shift 2 ;;
      --result) RESULT="$2"; shift 2 ;;
      --memory-type) MEMORY_TYPE="$2"; shift 2 ;;
      --scope) SCOPE="$2"; shift 2 ;;
      --confidence) CONFIDENCE="$2"; shift 2 ;;
      --decay) DECAY="$2"; shift 2 ;;
      --tag) TAGS="${TAGS}$2
"; shift 2 ;;
      --validated) VALIDATED="true"; shift ;;
      *) usage; exit 2 ;;
    esac
  done
  [ -n "$PATCH_ID" ] || { usage; exit 2; }
  patch="$(find_patch "$STORE" "$PATCH_ID")"
  [ -n "$patch" ] || { echo "patch not found: $PATCH_ID" >&2; exit 1; }
  if [ "$(printf "%s" "$patch" | jq -r .status)" = "applied" ]; then
    jq -n --arg id "$PATCH_ID" '{id:$id, already_applied:true}'
    return
  fi

  kind="$(printf "%s" "$patch" | jq -r .kind)"
  reason="$(printf "%s" "$patch" | jq -r .reason)"
  event_id="$(new_id event)"
  event="$(jq -n --arg id "$event_id" --arg ts "$(now)" --arg type patch \
    --arg text "Applied $kind patch $PATCH_ID: $reason" --arg source agent --arg ref "$PATCH_ID" --arg tag1 memory-patch --arg tag2 "$kind" \
    '{id:$id, ts:$ts, type:$type, text:$text, source:$source, refs:[$ref], tags:[$tag1,$tag2]}')"
  append_jsonl "$STORE/events.jsonl" "$(printf "%s" "$event" | jq -c .)"

  case "$kind" in
    add_memory|update_memory|deprecate_memory)
      target="$(printf "%s" "$patch" | jq -r .target)"
      after="$(printf "%s" "$patch" | jq -r .after)"
      before="$(printf "%s" "$patch" | jq -r .before)"
      memory_id="$target"
      [ -n "$memory_id" ] || memory_id="$(new_id mem)"
      status="active"
      content="$after"
      [ "$kind" = "deprecate_memory" ] && status="deprecated"
      [ "$kind" = "deprecate_memory" ] && [ -z "$content" ] && content="$before"
      created_at="null"
      [ "$kind" = "add_memory" ] && created_at="\"$(now)\""
      validated_at="null"
      [ "$VALIDATED" = "true" ] && validated_at="\"$(now)\""
      supersedes="null"
      [ "$kind" = "update_memory" ] && supersedes="\"$target\""
      source_json="$(printf "%s" "$patch" | jq --arg event "$event_id" '.evidence as $e | if ($e|length) > 0 then $e else [$event] end')"
      memory="$(jq -n \
        --arg id "$memory_id" --arg type "$MEMORY_TYPE" --arg scope "$SCOPE" --arg content "$content" --arg status "$status" \
        --argjson confidence "$CONFIDENCE" --arg event "$event_id" --arg updated_at "$(now)" --arg decay "$DECAY" \
        --argjson tags "$(lines_json "$TAGS")" --argjson source "$source_json" \
        --argjson created_at "$created_at" --argjson validated_at "$validated_at" --argjson supersedes "$supersedes" \
        '{id:$id, type:$type, scope:$scope, content:$content, status:$status, confidence:$confidence, source:$source, created_at:$created_at, updated_at:$updated_at, last_used_at:null, last_validated_at:$validated_at, decay:$decay, tags:$tags, supersedes:$supersedes}')"
      append_jsonl "$STORE/long_term/facts.jsonl" "$(printf "%s" "$memory" | jq -c .)"
      ;;
  esac

  [ -n "$RESULT" ] || RESULT="applied"
  updated="$(printf "%s" "$patch" | jq --arg ts "$(now)" --arg result "$RESULT" '.status="applied" | .applied_at=$ts | .result=$result')"
  rewrite_patch "$STORE" "$PATCH_ID" "$(printf "%s" "$updated" | jq -c .)"
  jq -n --argjson patch "$updated" --argjson event "$event" '{patch:$patch, event:$event}'
}

cmd_eval_result() {
  parse_common_store
  ID=""
  CASE=""
  PATCH=""
  BEFORE=""
  AFTER=""
  NOTES=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --store) STORE="$2"; shift 2 ;;
      --id) ID="$2"; shift 2 ;;
      --case) CASE="$2"; shift 2 ;;
      --patch) PATCH="$2"; shift 2 ;;
      --before) BEFORE="$2"; shift 2 ;;
      --after) AFTER="$2"; shift 2 ;;
      --notes) NOTES="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [ -n "$CASE" ] && [ -n "$BEFORE" ] && [ -n "$AFTER" ] || { usage; exit 2; }
  [ -n "$ID" ] || ID="$(new_id run)"
  json="$(jq -n --arg id "$ID" --arg case "$CASE" --arg patch "$PATCH" --argjson before "$BEFORE" --argjson after "$AFTER" --arg notes "$NOTES" --arg ts "$(now)" \
    '{id:$id, case:$case, patch:$patch, before:$before, after:$after, notes:$notes, ts:$ts}')"
  append_jsonl "$STORE/evals/runs.jsonl" "$(printf "%s" "$json" | jq -c .)"
  printf "%s\n" "$json"
}

cmd_list() {
  parse_common_store
  WHAT=""
  LIMIT="20"
  if [ "$#" -gt 0 ]; then
    WHAT="$1"
    shift
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --store) STORE="$2"; shift 2 ;;
      --limit) LIMIT="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  case "$WHAT" in
    events) path="$STORE/events.jsonl" ;;
    patches) path="$STORE/meta/patches.jsonl" ;;
    facts) path="$STORE/long_term/facts.jsonl" ;;
    evals) path="$STORE/evals/runs.jsonl" ;;
    *) usage; exit 2 ;;
  esac
  [ -f "$path" ] || exit 0
  tail -n "$LIMIT" "$path"
}

need_jq
[ "$#" -gt 0 ] || { usage; exit 2; }
cmd="$1"
shift
case "$cmd" in
  init) cmd_init "$@" ;;
  event) cmd_event "$@" ;;
  patch) cmd_patch "$@" ;;
  apply) cmd_apply "$@" ;;
  eval-result) cmd_eval_result "$@" ;;
  list) cmd_list "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
