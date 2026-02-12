# Codex PR Review

A Claude Code skill that reviews pull requests using [OpenAI Codex](https://openai.com/index/introducing-codex/) for independent, cross-model code review. Get a second opinion on any PR without leaving Claude Code.

## What It Does

When you run `/codex-pr-review`, the skill:

1. Detects the PR from your current branch (or takes a PR number/URL)
2. Gathers the diff and any `CLAUDE.md` project rules
3. Sends everything to Codex with a structured review prompt
4. Posts the review as a PR comment with findings, confidence scores, and a verdict

Findings are filtered by a configurable confidence threshold (default 0.8) so you only see issues the model is genuinely certain about.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- [Codex CLI](https://github.com/openai/codex) installed (`npm install -g @openai/codex`)
- Codex authenticated via OAuth (`codex login`) -- headless mode requires OAuth, not an API key
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated
- [jq](https://jqlang.github.io/jq/) installed

## Installation

```bash
git clone https://github.com/johnpsasser/codex-pr-review.git
cd codex-pr-review
./install.sh
```

Then restart Claude Code.

## Usage

```
/codex-pr-review                             # Auto-detect PR for current branch
/codex-pr-review 123                         # Review PR #123
/codex-pr-review https://github.com/.../42   # Review by URL
/codex-pr-review --threshold 0.6             # Lower confidence threshold
/codex-pr-review 123 --model gpt-5.2-codex  # Use a different model
```

### Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `PR_NUMBER` or `PR_URL` | auto-detect | PR to review. If omitted, detects from current branch |
| `--threshold` | `0.8` | Minimum confidence score (0-1) for reporting findings |
| `--model` | `gpt-5.3-codex` | Codex model to use |

## How It Works

The skill builds a structured prompt from a template (`scripts/codex-prompt.md`) that includes:

- The PR diff
- Any `CLAUDE.md` project rules found in the repo root
- Review criteria covering correctness, security, performance, and maintainability

Codex returns structured JSON matching the output schema (`scripts/codex-output-schema.json`), which includes:

- Individual findings with title, body, confidence score, priority, and code location
- An overall correctness verdict with explanation

The script then formats the results into a readable PR comment with a summary table and expandable details.

### Output Schema

Each finding includes:

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Short summary (max 80 chars) |
| `body` | string | Detailed explanation with suggested fix |
| `confidence_score` | number (0-1) | How confident the model is this is a real issue |
| `priority` | int (0-3) | 0=info, 1=low, 2=medium, 3=high |
| `code_location` | object | File path, start line, end line |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success -- review posted |
| 1 | Missing prerequisite (codex, gh, or OAuth not configured) |
| 2 | PR not found or empty diff |
| 3 | Codex execution failed |
| 4 | Failed to post PR comment (review still printed to stdout) |

## Project Structure

```
codex-pr-review/
├── SKILL.md                           # Claude Code skill definition
├── install.sh                         # One-step installer
├── LICENSE
├── README.md
└── scripts/
    ├── review.sh                      # Main orchestration script
    ├── codex-prompt.md                # Review prompt template
    └── codex-output-schema.json       # Structured output schema
```

## License

MIT
