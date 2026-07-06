#!/usr/bin/env bash
# install.sh - install the claude-watch-windows status line from Git Bash.
#
# Recommended on managed / corporate Windows: Git Bash is NOT subject to the
# PowerShell execution policy, so this works even where install.ps1 is blocked
# by Group Policy. Run it from the repo folder:
#
#     bash install.sh
#
# Idempotent. Backs up settings.json, merges in the statusLine, and removes any
# obsolete fetch-usage.sh hooks - without touching your other keys or hooks.

set -u

pkg="$(cd "$(dirname "$0")" && pwd)"
claude="$HOME/.claude"
cmds="$claude/commands"
settings="$claude/settings.json"

echo "claude-watch-windows installer (Git Bash)"
echo "Target: $claude"
echo

# --- 0. preflight: required files present? ---
missing=0
for f in statusline-command.sh tokmark.sh commands/tok.md; do
  [ -f "$pkg/$f" ] || { echo "[!!] missing file: $f (run this from the repo folder)"; missing=1; }
done
[ "$missing" -eq 1 ] && { echo "Aborting - incomplete download."; exit 1; }

mkdir -p "$cmds"

# --- 1. copy scripts + slash command ---
cp "$pkg/statusline-command.sh" "$claude/"
cp "$pkg/tokmark.sh"            "$claude/"
cp "$pkg/commands/tok.md"       "$cmds/"
echo "[ok] copied statusline-command.sh, tokmark.sh, commands/tok.md"

# --- 2. ensure jq (prefer bundled, then PATH, then ~/.claude) ---
JQ=""
if [ -f "$pkg/jq.exe" ]; then
  cp "$pkg/jq.exe" "$claude/jq.exe"; JQ="$claude/jq.exe"; echo "[ok] installed bundled jq.exe"
elif command -v jq >/dev/null 2>&1; then
  JQ="jq"; echo "[ok] jq found on PATH"
elif [ -f "$claude/jq.exe" ]; then
  JQ="$claude/jq.exe"; echo "[ok] jq.exe already present in ~/.claude"
else
  echo "[!!] jq not found and not bundled. Put a jq.exe next to install.sh (or in ~/.claude) and re-run."
  exit 1
fi

# --- 3. merge settings.json safely (handles fresh / existing / old claude-watch / broken) ---
# jq program: set statusLine, strip any fetch-usage.sh hook groups, drop emptied events.
MERGE='
  .statusLine = {type:"command", command:"bash ~/.claude/statusline-command.sh"}
  | ( if (.hooks|type) == "object" then
        .hooks |= with_entries(
          .value |= ( if type == "array"
            then map( select( ((.hooks // []) | map(.command // "") | any(test("fetch-usage\\.sh"))) | not ) )
            else . end ) )
        | .hooks |= with_entries( select( (.value|type) != "array" or (.value|length) > 0 ) )
      else . end )
'

if [ -f "$settings" ]; then
  if "$JQ" empty "$settings" >/dev/null 2>&1; then
    cp "$settings" "$settings.bak-statusline"
    echo "[ok] backed up settings.json -> settings.json.bak-statusline"
    tmp="$settings.tmp.$$"
    if "$JQ" "$MERGE" "$settings" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      mv "$tmp" "$settings"
      echo "[ok] merged statusLine into settings.json"
    else
      rm -f "$tmp"
      echo "[!!] merge failed; settings.json left unchanged (backup is safe)."; exit 1
    fi
  else
    echo "[!!] existing settings.json is not valid JSON. Fix or remove it, then re-run."
    echo "     (Left untouched - nothing was changed.)"; exit 1
  fi
else
  echo '{}' | "$JQ" '.statusLine = {type:"command", command:"bash ~/.claude/statusline-command.sh"}' > "$settings"
  echo "[ok] created settings.json with statusLine"
fi

echo
echo "Done. Restart Claude Code to see the status line."
echo "Arm the token marker with /tok (or 'bash ~/.claude/tokmark.sh'); /tok clear to reset."
