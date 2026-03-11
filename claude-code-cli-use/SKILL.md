---
name: claude-code-cli-use
description: "How to use Claude Code's CLI programmatically via `claude -p` (headless mode) to run tasks non-interactively, get structured output, stream responses, control tool permissions, chain conversations, and integrate into scripts/CI/CD pipelines. Use this skill whenever the user wants to: run Claude Code from a shell script or automation pipeline, call Claude Code programmatically, use headless mode, get JSON output from Claude, chain multiple Claude invocations, integrate Claude Code into CI/CD (GitHub Actions, GitLab CI), build tooling on top of Claude Code CLI, control which tools Claude can use in automated runs, or asks about `claude -p` / `--print` flags. Even if the user doesn't say 'headless' explicitly — if they're asking how to script, automate, or programmatically invoke Claude Code, this skill applies."
---

# Claude Code CLI Programmatic Usage (`claude -p`)

The `claude -p` (or `--print`) flag runs Claude Code non-interactively — it takes a prompt, executes it, prints the response, and exits. This is the foundation for all scripting, automation, and CI/CD integration with Claude Code.

> Previously called "headless mode." The `-p` flag and all CLI options work the same way.

## Basic usage

```bash
# Simple question — prints text response and exits
claude -p "What does the auth module do?"

# Pipe content as input
cat logs.txt | claude -p "Explain these errors"
git diff | claude -p "Review this diff for bugs"

# Pipe a PR diff for review
gh pr diff 42 | claude -p "Review for security vulnerabilities"
```

The prompt can come from an argument or from stdin (piped content). When both are present, the piped content becomes context and the argument is the instruction.

## Output formats

Control what `claude -p` returns with `--output-format`:

| Format        | Description                                     |
|---------------|-------------------------------------------------|
| `text`        | (default) Plain text, just the response         |
| `json`        | JSON object with `result`, `session_id`, metadata |
| `stream-json` | Newline-delimited JSON events for real-time streaming |

### Plain text (default)

```bash
claude -p "Summarize this project"
# → prints plain text response
```

### JSON output

Returns a JSON object containing the text result in the `result` field, plus `session_id` and usage metadata. Useful for scripting because you can parse the response programmatically.

```bash
claude -p "Summarize this project" --output-format json

# Extract just the text result with jq
claude -p "Summarize this project" --output-format json | jq -r '.result'
```

### Structured output with JSON Schema

When you need the response to conform to a specific shape, combine `--output-format json` with `--json-schema`. The structured data appears in the `structured_output` field (not `result`).

```bash
# Extract function names as a typed array
claude -p "Extract the main function names from auth.py" \
  --output-format json \
  --json-schema '{"type":"object","properties":{"functions":{"type":"array","items":{"type":"string"}}},"required":["functions"]}'

# Parse the structured output
claude -p "List all API endpoints" \
  --output-format json \
  --json-schema '{"type":"object","properties":{"endpoints":{"type":"array","items":{"type":"object","properties":{"method":{"type":"string"},"path":{"type":"string"}}}}}}' \
  | jq '.structured_output'
```

### Streaming output

For real-time token-by-token output, use `stream-json` with `--verbose` and `--include-partial-messages`:

```bash
# Full event stream — each line is a JSON event
claude -p "Explain recursion" \
  --output-format stream-json --verbose --include-partial-messages

# Filter for just the text tokens using jq
claude -p "Write a poem" \
  --output-format stream-json --verbose --include-partial-messages | \
  jq -rj 'select(.type == "stream_event" and .event.delta.type? == "text_delta") | .event.delta.text'
```

## Tool permissions (`--allowedTools`)

In `-p` mode, Claude cannot prompt the user for permission. Use `--allowedTools` to pre-authorize specific tools so Claude can act autonomously.

### Common patterns

```bash
# Allow all common tools (closest to "YOLO mode")
claude -p "Fix all lint errors" \
  --allowedTools "Bash(*),Read,Edit,Write,Glob,Grep"

# Allow only read operations
claude -p "Analyze this codebase" \
  --allowedTools "Read,Glob,Grep"

# Allow read + specific Bash commands
claude -p "Run tests and report results" \
  --allowedTools "Read,Bash(npm test *),Bash(npm run *)"
```

### Permission rule syntax

Rules follow the format `Tool` or `Tool(specifier)`:

| Rule                     | Matches                                      |
|--------------------------|----------------------------------------------|
| `Bash`                   | All Bash commands                            |
| `Bash(npm run *)`        | Commands starting with `npm run `            |
| `Bash(git diff *)`       | Commands starting with `git diff `           |
| `Read`                   | All file reads                               |
| `Read(./.env)`           | Reading `.env` only                          |
| `Edit`                   | All file edits                               |
| `WebFetch(domain:example.com)` | Fetch requests to example.com          |

The trailing ` *` enables prefix matching. The space before `*` matters: `Bash(git diff *)` matches `git diff HEAD` but not `git diff-index`. Without the space, `Bash(git diff*)` would also match `git diff-index`.

### Practical examples

```bash
# Git operations only
claude -p "Look at staged changes and create a commit" \
  --allowedTools "Bash(git diff *),Bash(git log *),Bash(git status *),Bash(git commit *)"

# Full autonomy — skip all permission prompts
claude -p "Refactor the auth module" \
  --dangerously-skip-permissions

# Or, the safer version — allow specific tools
claude -p "Refactor the auth module" \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep"
```

## Continuing conversations

Conversations can be continued across multiple `claude -p` invocations, letting you build multi-step workflows.

### Continue the most recent conversation

```bash
claude -p "Review this codebase for performance issues"
claude -p "Now focus on the database queries" --continue
claude -p "Generate a summary of all issues found" --continue
```

### Resume a specific session by ID

```bash
# Capture session ID from JSON output
session_id=$(claude -p "Start a code review" --output-format json | jq -r '.session_id')

# Resume that specific session later
claude -p "What did you find?" --resume "$session_id"
```

This is essential when running multiple parallel conversations — `--continue` always picks the most recent, while `--resume` targets a specific session.

## System prompt customization

Four flags let you control Claude's system prompt:

| Flag                          | Behavior                        |
|-------------------------------|---------------------------------|
| `--append-system-prompt`      | **Appends** text to the default prompt (recommended) |
| `--append-system-prompt-file` | **Appends** from a file         |
| `--system-prompt`             | **Replaces** the entire default prompt |
| `--system-prompt-file`        | **Replaces** from a file        |

`--append-system-prompt` is safest for most use cases — it keeps Claude Code's built-in capabilities while adding your instructions. Use `--system-prompt` only when you need complete control.

```bash
# Add a role while keeping defaults
gh pr diff "$PR" | claude -p \
  --append-system-prompt "You are a security engineer. Focus on vulnerabilities." \
  --output-format json

# Full custom prompt
claude -p "Analyze this code" \
  --system-prompt "You are a Python expert. Only respond about Python code."

# Load from file (good for version control)
claude -p "Review this PR" \
  --append-system-prompt-file ./prompts/review-rules.txt
```

## Other useful flags for `-p` mode

| Flag                    | What it does                                              |
|-------------------------|-----------------------------------------------------------|
| `--max-turns N`         | Limit agentic turns; exits with error when reached        |
| `--max-budget-usd N`   | Cap spending on API calls                                 |
| `--model <model>`       | Use a specific model (`sonnet`, `opus`, or full model ID) |
| `--fallback-model`      | Auto-fallback model when primary is overloaded            |
| `--verbose`             | Show full turn-by-turn output                             |
| `--no-session-persistence` | Don't save the session to disk                         |
| `--add-dir <path>`      | Add extra working directories                             |
| `--mcp-config <file>`   | Load MCP servers from a JSON config                       |
| `--tools "Bash,Edit"`   | Restrict which tools are available (vs `--allowedTools` which auto-approves) |
| `--disallowedTools`     | Remove specific tools entirely                            |
| `--dangerously-skip-permissions` | Skip all permission prompts (use with extreme caution) |

The difference between `--tools` and `--allowedTools`: `--tools` restricts which tools exist (Claude can't use tools not listed). `--allowedTools` auto-approves listed tools (Claude can still use others, but will need permission).

## Real-world recipes

### CI/CD: Auto-fix lint errors and commit

```bash
claude -p "Run eslint, fix all errors, and commit the changes" \
  --allowedTools "Bash(npx eslint *),Bash(git *),Read,Edit" \
  --max-turns 10
```

### Script: Extract info from codebase as JSON

```bash
claude -p "List all REST API endpoints with their HTTP methods and paths" \
  --output-format json \
  --json-schema '{"type":"object","properties":{"endpoints":{"type":"array","items":{"type":"object","properties":{"method":{"type":"string"},"path":{"type":"string"},"handler":{"type":"string"}},"required":["method","path"]}}},"required":["endpoints"]}' \
  | jq '.structured_output.endpoints'
```

### Multi-step workflow with session chaining

```bash
# Step 1: Analyze
session_id=$(claude -p "Analyze the test failures in this repo" \
  --allowedTools "Bash(npm test *),Read,Glob,Grep" \
  --output-format json | jq -r '.session_id')

# Step 2: Fix (same session, has full context)
claude -p "Now fix the issues you found" \
  --resume "$session_id" \
  --allowedTools "Read,Edit,Bash(npm test *)"

# Step 3: Verify
claude -p "Run the tests again to confirm the fixes" \
  --resume "$session_id" \
  --allowedTools "Bash(npm test *)" \
  --output-format json | jq -r '.result'
```

### Parallel execution with different models

```bash
# Run the same review with different models and compare
claude -p "Review auth.py for security issues" --model sonnet --output-format json > review-sonnet.json &
claude -p "Review auth.py for security issues" --model opus --output-format json > review-opus.json &
wait
```

### Pipe chain: generate then validate

```bash
# Generate code, then validate it in a second pass
claude -p "Write a Python function to parse CSV files" \
  --output-format json | jq -r '.result' | \
  claude -p "Review this code for bugs and edge cases"
```

## Important notes

- Skills (like `/commit`) and built-in slash commands are only available in interactive mode. In `-p` mode, describe the task directly instead.
- Stdin (piped content) and the `-p` argument are combined — the pipe is context, the argument is the instruction.
- `--dangerously-skip-permissions` is powerful but risky; prefer `--allowedTools` with specific patterns for production use.
- Use `--max-turns` and `--max-budget-usd` as safety guardrails in automated pipelines.
