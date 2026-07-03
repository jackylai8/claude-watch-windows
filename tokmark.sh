#!/bin/sh
# tokmark.sh - control the status-line in/out token marker (for skill evaluation).
#
#   bash ~/.claude/tokmark.sh          set   - Δ in/out counts from this point on
#   bash ~/.claude/tokmark.sh clear    clear - status line shows cumulative again
#
# Workflow: run `set` right before invoking a skill, then read the Δ in/out on
# line 2 of the status line - that is the skill's exact token footprint, including
# every tool-loop turn it triggered.
case "${1:-set}" in
  clear|reset|off|-c)
    rm -f /tmp/.claude_tokbase_* /tmp/.claude_tokmark_req
    echo "token marker cleared - status line shows cumulative in/out again"
    ;;
  *)
    : > /tmp/.claude_tokmark_req
    echo "token marker armed - Delta in/out will count from the next status-line refresh"
    ;;
esac
