# /orchestra — AI Orchestrator

Launch Orchestra Brain to manage complex tasks with a team of AI workers.

## Triggers
- `/orchestra`
- `запусти оркестратор`
- `orchestra`
- `run orchestra`

## What it does

Orchestra is an autonomous AI orchestrator that decomposes complex tasks into subtasks, spawns worker Claude Code processes in tmux windows, reviews their output, and assembles the final result.

## Setup

Before first use, ensure the Orchestra repo is cloned and the path below is correct.

```bash
ORCHESTRA_DIR="$HOME/orchestra"  # adjust if needed
```

## Instructions

When this skill is invoked:

1. **Check if `.brain/` exists in the current project directory.**

   If `.brain/` does NOT exist:
   ```bash
   ORCHESTRA_DIR="$HOME/orchestra"

   # Copy orchestrator structure to current project
   cp -n "$ORCHESTRA_DIR/CLAUDE.md" ./CLAUDE.md
   cp -rn "$ORCHESTRA_DIR/.brain" ./.brain
   cp -rn "$ORCHESTRA_DIR/memory" ./memory
   mkdir -p .claude/commands
   cp -n "$ORCHESTRA_DIR/.claude/commands/review.md" ./.claude/commands/review.md
   cp -n "$ORCHESTRA_DIR/.claude/commands/review-check.md" ./.claude/commands/review-check.md
   ```

   Tell the user: "Orchestra initialized in current project. Restart Claude Code to load the Brain system prompt (`CLAUDE.md`)."

2. **If `.brain/` already exists:**

   Read `.brain/state.json`:

   - If `status == "idle"` — tell the user: "Orchestra is ready. Give me a task and I'll orchestrate it."
   - If `status != "idle"` — read `next_action` and resume the interrupted task. Tell the user what's being resumed.

3. **Then follow the Brain protocol from `CLAUDE.md`:**
   - Classify the task (Trivial/Simple/Moderate/Complex)
   - Create plan in `.brain/plan.md`
   - Spawn workers via `bash .brain/scripts/spawn-worker.sh`
   - Monitor, review, collect results

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- `tmux` installed
- `jq` installed

## Notes

- Trivial tasks (1 file, <20 lines) are done directly, no workers spawned
- Maximum 8 workers simultaneously
- Workers communicate through files in `.brain/` (tasks, signals, results)
- Use `bash .brain/scripts/monitor.sh --watch` in a separate terminal for real-time monitoring
