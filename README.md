# Orchestra

AI orchestrator built on [Claude Code](https://docs.anthropic.com/en/docs/claude-code) + tmux. One Claude Code process (the Brain) manages a team of workers (other Claude Code processes) through tmux windows.

## How it works

```
You ──→ Brain (Claude Code) ──→ tmux session
                                  ├── worker-01 (coder)
                                  ├── worker-02 (tester)
                                  └── worker-03 (writer)
```

1. You give the Brain a task
2. Brain classifies it (trivial → does it itself, complex → spawns workers)
3. Workers execute in parallel tmux windows with strict file ownership
4. Brain reviews results, requests rework if needed
5. Output collected in `output/`

## Key features

- **Phased execution** — dependent tasks run sequentially, independent ones in parallel
- **5C prompts** — Context, Command, Constraints, Criteria, Completion for every worker task
- **Signal files** — lightweight monitoring via `ls .brain/signals/` instead of JSON polling
- **Adaptive polling** — 3 min initial wait, then 60s checks (workers usually finish during the pause)
- **Cold restart** — `state.json` tracks `next_action`, interrupted tasks resume automatically
- **Code review** — built-in `/review` command spawns a parallel reviewer
- **Memory system** — patterns and anti-patterns accumulate across sessions

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
```

## Quick start

```bash
git clone https://github.com/222dotcrypto/orchestra.git
cd orchestra
claude
```

Claude Code picks up `CLAUDE.md` automatically — it becomes the Brain's system prompt.

Give it a task:

```
Create a REST API with FastAPI, endpoints /users and /posts, pytest tests, and a Dockerfile.
```

The Brain will plan, spawn workers, review results, and collect output.

## Monitoring

In a separate terminal:

```bash
# One-time status snapshot
bash .brain/scripts/monitor.sh

# Auto-refresh every 5 seconds
bash .brain/scripts/monitor.sh --watch
```

Or attach to the tmux session directly:

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

Floating desktop widget showing active workers, tasks, and token usage in real-time.

## Commands

| Command | Description |
|---------|-------------|
| `/review` | Run parallel code review of changed files |
| `/review full` | Review entire project |
| `/review-check` | Check review results and apply fixes |

## Project structure

```
orchestra/
├── CLAUDE.md                     # Brain system prompt (the orchestrator)
├── .brain/
│   ├── WORKER_PROTOCOL.md        # Worker protocol (read by workers at start)
│   ├── state.json                # Orchestrator state (cold restart support)
│   ├── scripts/                  # Management scripts
│   │   ├── spawn-worker.sh       # Launch worker in tmux
│   │   ├── run-worker.sh         # Worker runner (called from tmux)
│   │   ├── kill-worker.sh        # Stop workers
│   │   ├── check-workers.sh      # Health check (tmux/ps)
│   │   └── monitor.sh            # System status display
│   ├── tasks/                    # Task JSON files (created per run)
│   ├── workers/                  # Worker state (created per run)
│   ├── results/                  # Task results (created per run)
│   ├── prompts/                  # Generated worker prompts
│   │   └── templates/            # Reusable prompt templates
│   ├── logs/                     # Brain and worker logs
│   ├── signals/                  # Completion markers
│   └── inbox/                    # Materials for content pipeline
├── memory/                       # Long-term memory (persists across sessions)
│   ├── patterns.md               # What works
│   ├── anti-patterns.md          # What doesn't work
│   ├── worker-profiles.md        # Effective prompts by role
│   └── task-templates/           # Ready-made task templates
├── widget/                       # Electron monitoring dashboard
├── skills/                       # Skills
│   └── orchestra/                # /orchestra skill
├── output/                       # Run results (gitignored)
└── .claude/
    └── commands/                 # Slash commands (/review, /review-check)
```

## How workers communicate

Workers and the Brain communicate through files:

- **Tasks**: `.brain/tasks/task-{id}.json` — Brain creates, workers read and update status
- **Signals**: `.brain/signals/task-{id}.review` — workers create when done, Brain checks via `ls`
- **Results**: `.brain/results/task-{id}-result.md` — workers write, Brain reviews
- **Logs**: `.brain/logs/` — everyone writes

## Task classification

| Class | Criteria | Strategy |
|-------|----------|----------|
| Trivial | 1 file, <20 lines | Brain does it itself |
| Simple | 1-2 files, single skill | 1 worker |
| Moderate | 3-5 files, 2+ skills | 2-3 workers, 1-2 phases |
| Complex | Many files, many skills | 4-8 workers, 3+ phases |

## Content pipeline

For analyzing materials (exported chats, notes, logs):

1. Place files in `.brain/inbox/`
2. Tell the Brain: "Analyze materials from inbox and create [posts / guide / thread]"
3. Results appear in `.brain/results/content/`

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Worker won't start | Check that prompt exists in `.brain/prompts/` |
| tmux session not found | Scripts create it automatically on first spawn |
| Worker stuck | `bash .brain/scripts/kill-worker.sh worker-XX` and restart |
| Brain doesn't see results | Check worker wrote to the correct `result_path` |

## License

MIT
