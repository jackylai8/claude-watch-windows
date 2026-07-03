---
allowed-tools: Bash(bash ~/.claude/tokmark.sh:*)
argument-hint: [clear]
description: Arm the in/out token marker for skill evaluation — line 2 of the status line then shows Δ in/out since this point. Use "/tok clear" to reset to cumulative.
---

!`bash ~/.claude/tokmark.sh $ARGUMENTS`

The token-marker script above has just run. In one short sentence, tell the user whether the marker was **armed** or **cleared** (infer from the output), and that the status line's line 2 will show Δ in/out from here (or cumulative again if cleared). Do nothing else — do not read files or run other tools.
