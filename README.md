# claude-watch-windows

A rich, three-line status line for **[Claude Code](https://code.claude.com)** on
**Windows / Git Bash**. Shows your model, git status, session cost, **in/out token
usage**, rate limits, and context window — at a glance, always visible.

```
Opus 4.8 (1M - xHigh) | my-project • main +1 ●2 ↑1
$2.91 | in 37k • out 392k
5h 5% (2h 10m) • 7d 27% (5d 3h) | ctx 28% (140k/500k) | 41m (18m api)
```

- **Line 1 — orientation:** model + reasoning effort · folder · git branch and status
- **Line 2 — this session:** cost · in/out tokens (cumulative, or **Δ since a marker**) 
- **Line 3 — limits:** 5-hour & 7-day usage (with reset countdowns) · context window · duration

Everything is read from the JSON Claude Code pipes to the status line on stdin —
**no API calls, no credentials read** — except the in/out token totals, which are
summed from the session transcript (cached, ~160 ms once per turn).

Based on [xleddyl/claude-watch](https://github.com/xleddyl/claude-watch) (macOS),
re-adapted for Windows and extended with cost, git status, context colour-warnings,
and the token marker.

---

## What each part means

**Line 1**

| Part | Meaning |
|------|---------|
| `Opus 4.8 (1M - xHigh)` | model + reasoning effort (from `.model` / `.effort`) |
| `⚡` | shown only when fast mode is on |
| `my-project` | current folder |
| `main` | git branch |
| `+1` | staged files (green) |
| `●2` | modified files (amber) |
| `?3` | untracked files (grey) |
| `↑1 ↓2` | commits ahead / behind upstream |

**Line 2**

| Part | Meaning |
|------|---------|
| `$2.91` | cumulative session cost (from `.cost.total_cost_usd`) |
| `in 37k • out 392k` | cumulative input / output tokens for the session |
| `Δ in 1,842 • out 6,504` | with a marker set: tokens **since the mark** (see below) |

**Line 3**

| Part | Meaning |
|------|---------|
| `5h 5% (2h 10m)` | 5-hour rate-limit usage + time to reset |
| `7d 27% (5d 3h)` | 7-day rate-limit usage + time to reset |
| `ctx 28% (140k/500k)` | context-window usage; **amber ≥80%, red ≥90%** or over 200k |
| `41m (18m api)` | wall-clock session duration (time spent in the API) |

---

## The `/tok` token marker — measure a skill's footprint

`/context` shows what's *in* the context window but never your cumulative **output**
tokens. This status line does — and the `/tok` marker lets you isolate a single
skill/command's exact in/out cost, including every tool-loop turn it triggers.

```
/tok            # right before you run the skill  → line 2 switches to "Δ in X • out Y"
...run the skill...
                # read line 2: that's the skill's exact token footprint
/tok clear      # back to cumulative
```

`/tok` is a user-level slash command (available in every project/session). Under the
hood it runs `~/.claude/tokmark.sh`, which drops a sentinel file; the status line
snapshots the token counts on its next refresh and then shows the delta.

You can also arm it without the slash command:

```bash
bash ~/.claude/tokmark.sh          # arm
bash ~/.claude/tokmark.sh clear    # reset to cumulative
```

---

## Requirements

- **Claude Code** on Windows — installs Git Bash, which provides `bash`, `git`, `sed`, `stat`, `date`.
- **jq** — **bundled** as `jq.exe` in this repo; the installer copies it into `~/.claude`.
  No separate install, no winget, no admin rights needed.
- **Claude Code ≥ 2.1.x** — the status line reads `rate_limits` from stdin, added in 2.1.

---

## Install

Clone or download the **whole repo** (not just one file), then pick one:

### Recommended — Git Bash  ✅ works on managed/corporate PCs

Open **Git Bash** (ships with Claude Code / Git for Windows), `cd` into the folder, and:

```bash
bash install.sh
```

Then **restart Claude Code**. Git Bash is not subject to the PowerShell execution
policy, so this works even on locked-down machines where `install.ps1` is blocked.

### Alternative — PowerShell

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

> **Managed PC?** If your company enforces the execution policy via Group Policy,
> even `-ExecutionPolicy Bypass` is ignored and this will fail with red errors.
> First try `Unblock-File .\install.ps1`; if it's still blocked, **use `install.sh`
> above** — that's what it's for.

Both installers are idempotent. They copy the scripts into `%USERPROFILE%\.claude\`,
copy `tok.md` into `.claude\commands\`, drop in the bundled `jq.exe`, merge
`statusLine` into your `settings.json` (backing it up to `settings.json.bak-statusline`),
and remove any obsolete `fetch-usage.sh` hooks from earlier claude-watch versions —
without touching your other keys or hooks.

### Manual install (any OS with Git Bash / WSL)

```bash
cp statusline-command.sh tokmark.sh ~/.claude/
mkdir -p ~/.claude/commands && cp commands/tok.md ~/.claude/commands/
```
Then add to `~/.claude/settings.json`:
```json
"statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }
```
Restart Claude Code. (macOS needs GNU `date`/`stat`, or edit the `date -d` / `stat -c`
calls to their BSD equivalents.)

---

## Customising

Everything lives in `statusline-command.sh`:

- **Colours** — the `C_*` variables near the top (24-bit ANSI).
- **Context thresholds** — the `-ge 80` / `-ge 90` checks in the line-3 `ctx` block.
- **Layout** — the three `render` blocks at the bottom; segments are separated by
  `$SEP` (`•`) or `$PIPE` (`|`).
- Non-ASCII glyphs are hex-encoded (`\xNN`) so the file stays safe under cp1252.

---

## How it works

Claude Code runs your `statusLine.command` on every render and pipes it a JSON blob
on stdin: `.model`, `.effort`, `.workspace`, `.cost`, `.context_window`,
`.rate_limits`, `.transcript_path`, `.session_id`, etc. The script `jq`s out what it
needs. Rate limits and cost come straight from that blob (no network). In/out token
totals are summed from the transcript JSONL at `.transcript_path`, cached in
`/tmp/.claude_tokcache_<session>` keyed by the transcript's mtime+size so the parse
only runs once per turn.

---

## Troubleshooting

- **Status line blank after restart:** Claude Code may not resolve bare `bash`. Set the
  full path in `settings.json`, e.g.
  `"C:/Program Files/Git/bin/bash.exe" ~/.claude/statusline-command.sh`.
- **Line 2 tokens missing:** confirm `jq` runs in Git Bash (`jq --version`) and that
  `.transcript_path` exists.
- **Line 3 usage missing:** you're likely on Claude Code < 2.1 (no `rate_limits` on stdin).
- **`/tok` not found:** restart Claude Code so it picks up `~/.claude/commands/tok.md`.

## Uninstall

Restore `settings.json.bak-statusline` over `settings.json` (or delete the `statusLine`
key), and remove `~/.claude/statusline-command.sh`, `~/.claude/tokmark.sh`, and
`~/.claude/commands/tok.md`.

---

## License

MIT — see [LICENSE](LICENSE). Based on [xleddyl/claude-watch](https://github.com/xleddyl/claude-watch).
