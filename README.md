# Orchestra

AI orchestrator built on [Claude Code](https://docs.anthropic.com/en/docs/claude-code) + tmux. A Planner (Claude Code) creates a plan, then a Shell Runner executes it — spawning workers, waiting for signals, running checkpoints, and reviewing results. Claude is only called when thinking is needed; everything else is free bash.

## Architecture (v3)

```
You → Planner (Claude Code, one-shot)
         ↓ plan.yaml
       runner.sh (bash, $0)
         ├── spawn workers → tmux
         ├── wait for signals (.done/.failed)
         ├── check acceptance_signals
         ├── Checkpoint (Claude, quick) — between phases
         └── Reviewer (Claude, one-shot) — at the end
```

| Component | What it does | Cost |
|-----------|-------------|------|
| **Planner** | Classifies task, generates plan.yaml | $3-5 (one-shot) |
| **Runner** | Executes plan: spawn, wait, check | $0 (bash) |
| **Checkpoint** | Decides between phases: CONTINUE/ADJUST/ABORT | $1-2 (quick) |
| **Reviewer** | Final review of results | $5-7 (one-shot) |

## Requirements

```bash
# Claude Code CLI (must be installed and authenticated)
claude --version

# tmux
brew install tmux    # macOS
apt install tmux     # Linux

# jq
brew install jq      # macOS
apt install jq       # Linux

# Python 3 + PyYAML (for plan parsing)
pip install pyyaml
```

## Quick start

```bash
git clone https://github.com/222dotcrypto/orchestra.git
cd orchestra
claude
```

Claude Code picks up `CLAUDE.md` automatically — it becomes the Planner.

Give it a task:

```
Create a REST API with FastAPI, endpoints /users and /posts, pytest tests, and a Dockerfile.
```

The Planner will:
1. Classify complexity (1-10)
2. If 1-3: do it directly (DIY)
3. If 4-10: generate `plan.yaml` and run `bash runner.sh plan.yaml`

## Runner

The Shell Runner executes `plan.yaml` autonomously:

```bash
# Normal execution
bash runner.sh .brain/plan.yaml

# Dry run (no real Claude calls, logs what would happen)
bash runner.sh --dry-run .brain/plan.yaml
```

### Complexity scale

| Complexity | Strategy |
|-----------|----------|
| 1-3 | Planner does it itself (DIY) |
| 4-6 | 2-3 workers, 2 phases |
| 7-10 | 4-8 workers, 3+ phases, checkpoints |

## Monitoring

In a separate terminal:

```bash
# One-time status snapshot
bash .brain/scripts/monitor.sh

# Auto-refresh every 5 seconds
bash .brain/scripts/monitor.sh --watch
```

Or attach to the tmux session:

```bash
tmux attach -t orchestra
# Switch windows: Ctrl+B then window number
# List windows: Ctrl+B, W
```

## Widget (Electron dashboard)

```bash
cd widget
npm install
npm start
```

Floating desktop widget showing active workers, tasks, signals, and token usage in real-time.

## Commands

| Command | Description |
|---------|-------------|
| `/review` | Run parallel code review of changed files |
| `/review full` | Review entire project |
| `/review-check` | Check review results and apply fixes |

## Project structure

```
orchestra/
├── CLAUDE.md                     # Planner system prompt
├── runner.sh                     # Shell Runner (core of v3)
├── .brain/
│   ├── WORKER_PROTOCOL.md        # Worker protocol (read by workers at start)
│   ├── state.json                # Orchestrator state
│   ├── scripts/
│   │   ├── spawn-worker.sh       # Launch worker in tmux
│   │   ├── run-worker.sh         # Worker runner (called from tmux)
│   │   ├── kill-worker.sh        # Stop workers
│   │   ├── check-workers.sh      # Health check (tmux/ps)
│   │   ├── monitor.sh            # System status display
│   │   ├── yaml_to_json.py       # YAML→JSON converter for runner
│   │   ├── test-runner.sh        # Runner test harness
│   │   └── mock-worker.sh        # Mock worker for testing
│   ├── prompts/
│   │   └── templates/
│   │       ├── checkpoint.md     # Checkpoint prompt (between phases)
│   │       └── reviewer.md       # Reviewer prompt (final review)
│   ├── tasks/                    # Task JSON files (created per run)
│   ├── workers/                  # Worker state (created per run)
│   ├── results/                  # Task results (created per run)
│   ├── logs/                     # Runner and worker logs
│   ├── signals/                  # Completion markers (.done/.failed)
│   └── inbox/                    # Materials for content pipeline
├── memory/                       # Long-term memory (persists across sessions)
│   ├── patterns.md               # What works
│   ├── anti-patterns.md          # What doesn't work
│   ├── worker-profiles.md        # Effective prompts by role
│   └── task-templates/           # Ready-made task templates
├── widget/                       # Electron monitoring dashboard
├── skills/                       # Skills
│   └── orchestra/                # /orchestra skill
└── .claude/
    └── commands/                 # Slash commands (/review, /review-check)
```

## How workers communicate

Workers and the Runner communicate through files:

- **Tasks**: `.brain/tasks/task-{id}.json` — Runner creates, workers read and update status
- **Signals**: `.brain/signals/task-{id}.done` / `.failed` — workers create when finished
- **Results**: `.brain/results/task-{id}-result.md` — workers write output
- **Logs**: `.brain/logs/` — everyone writes

## Testing

```bash
# Run the test harness (uses --dry-run internally)
bash .brain/scripts/test-runner.sh

# Test YAML parsing
python3 .brain/scripts/yaml_to_json.py < .brain/plan.yaml | jq .

# Test runner in dry-run mode
bash runner.sh --dry-run .brain/plan.yaml
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Worker won't start | Check that prompt exists in `.brain/prompts/` |
| tmux session not found | Scripts create it automatically on first spawn |
| Worker stuck | `bash .brain/scripts/kill-worker.sh worker-XX` and restart |
| Runner can't parse YAML | Install PyYAML: `pip install pyyaml` |
| Checkpoint returns ABORT | Check runner.log for reason, fix plan and retry |

## License

MIT
