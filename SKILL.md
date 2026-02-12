---
name: codex-pr-review
description: Review a pull request using OpenAI Codex (gpt-5.3-codex). Use when the user wants an external AI code review via Codex, a second opinion on a PR, or a cross-model review. Supports auto-detection of current branch PR or explicit PR number/URL.
license: MIT
metadata:
  author: sasser
  version: 0.1.0
allowed-tools: Bash
argument-hint: "[PR_NUMBER|PR_URL] [--threshold FLOAT] [--model MODEL]"
---

# Codex PR Review

Review a pull request using OpenAI Codex for an independent, cross-model code review.

## Prerequisites

- `codex` CLI installed and on PATH
- `codex` authenticated via OAuth (`codex login`) — headless mode (`codex exec`) requires OAuth, not an API key
- `gh` CLI installed and authenticated
- Current directory must be a git repository

## Usage

```
/codex-pr-review                          # Auto-detect PR for current branch
/codex-pr-review 123                      # Review PR #123
/codex-pr-review --threshold 0.6          # Lower confidence threshold
/codex-pr-review 123 --model gpt-5.2-codex  # Use a specific model
```

## Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `PR_NUMBER` or `PR_URL` | auto-detect | PR to review. If omitted, detects from current branch |
| `--threshold` | `0.8` | Minimum confidence score (0-1) for reporting findings |
| `--model` | `gpt-5.3-codex` | Codex model to use |

## How to Execute This Skill

When this skill is invoked, run the review script:

```bash
bash $CLAUDE_PLUGIN_ROOT/scripts/review.sh [ARGS]
```

Where `[ARGS]` are the arguments the user passed after `/codex-pr-review`.

If `$CLAUDE_PLUGIN_ROOT` is not set, use the absolute path:

```bash
bash ~/.claude/skills/codex-pr-review/scripts/review.sh [ARGS]
```

### Interpreting Results

The script outputs JSON to stdout on success. Read the output and present it to the user as a formatted summary. If the script exits non-zero, display the error message to the user.

After the script succeeds, inform the user:
- How many findings were found vs. how many passed the threshold
- The overall correctness verdict and confidence
- That the review has been posted as a PR comment (with link)

### Error Handling

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success - review posted |
| 1 | Missing prerequisite (codex, gh, or OAuth not configured) |
| 2 | PR not found or not detectable |
| 3 | Codex execution failed |
| 4 | Failed to post comment |
