#!/bin/sh
# statusline-command.sh - Windows / Git Bash port of xleddyl/claude-watch
# Option D layout (3 lines) with full color theme + in/out token tracking:
#   line 1: model [fast glyph] | folder [• branch + git status]
#   line 2: session cost | in/out tokens (Δ since marker, else cumulative) | duration
#   line 3: 5h / 7d rate limits | context window (color-warns when high)
# Notes:
#   - rate limits read from stdin (.rate_limits) - no API fetch
#   - in/out tokens summed from the transcript (cached by mtime; ~160ms once per turn)
#   - token marker: `bash ~/.claude/tokmark.sh` snapshots counts, line 2 then shows
#     Δ in/out since that point (captures a skill's full multi-turn footprint);
#     `tokmark.sh clear` returns to cumulative.
#   - GNU `date -d`; ~/.claude on PATH for bundled jq.exe
#   - `printf '%s'` into jq; non-ASCII glyphs hex-encoded for cp1252-safe source
#   - Windows paths normalized (\ -> /) so basename yields the folder

export PATH="$HOME/.claude:$PATH"

input=$(cat)
J() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

# --- colors ---
C_MODEL="\033[1m\033[38;5;208m"           # orange bold
C_DIR="\033[1m\033[38;2;76;208;222m"      # cyan bold
C_BRANCH="\033[1m\033[38;2;192;103;222m"  # purple bold
C_GREY="\033[38;2;156;162;175m"           # grey
C_DIM="\033[2m\033[38;2;156;162;175m"     # dim grey
C_GREEN="\033[38;2;120;200;120m"          # green (output / added / ahead)
C_RED="\033[38;2;224;108;117m"            # red (removed / behind)
C_AMBER="\033[38;2;229;181;103m"          # amber (warn)
R="\033[0m"
SEP="\033[90m \xe2\x80\xa2 \033[0m"        # grey bullet
PIPE="\033[90m | \033[0m"
G_FAST="\xe2\x9a\xa1"                      # fast-mode bolt
G_UP="\xe2\x86\x91"                        # ahead arrow
G_DOWN="\xe2\x86\x93"                      # behind arrow
G_MOD="\xe2\x97\x8f"                       # modified dot
G_DELTA="\xce\x94"                         # delta
G_DOT="\xc2\xb7"                           # middle dot
G_BULLET="\xe2\x80\xa2"                    # bullet

# --- helpers ---
fmt_dur() {
  [ -z "$1" ] && return
  s=$(( $1 / 1000 )); h=$(( s / 3600 )); m=$(( (s % 3600) / 60 )); sec=$(( s % 60 ))
  if   [ "$h" -gt 0 ]; then printf '%sh %sm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%sm' "$m"
  else printf '%ss' "$sec"; fi
}
commafy() { printf '%s' "$1" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta'; }
fmt_tok() {
  n=${1:-0}
  if   [ "$n" -ge 1000000 ]; then printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  elif [ "$n" -ge 10000 ];   then printf '%dk' $(( n / 1000 ))
  elif [ "$n" -ge 1000 ];    then printf '%d.%dk' $(( n / 1000 )) $(( (n % 1000) / 100 ))
  else printf '%d' "$n"; fi
}

# --- model + reasoning effort ---
model=$(J '.model.display_name // ""')
effort=$(J '.effort.level // ""')
if [ -n "$effort" ]; then
  case "$effort" in
    [xX][hH][iI][gG][hH]) effort="xHigh" ;;
    *) effort="$(printf '%s' "$effort" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$effort" | cut -c2-)" ;;
  esac
  case "$model" in
    *"1M context"*) model=$(printf '%s' "$model" | sed "s/1M context/1M - ${effort}/") ;;
    *) model="${model} (${effort})" ;;
  esac
fi

# --- mode glyphs (thinking omitted: effectively always on) ---
glyphs=""
[ "$(J '.fast_mode // false')" = "true" ] && glyphs="${glyphs} ${G_FAST}"

# --- folder (normalize Windows backslashes so basename works) ---
dir=$(J '.workspace.current_dir // .cwd // ""')
dir=$(printf '%s' "$dir" | tr '\\' '/')
dir_name=$(basename "$dir")

# --- git branch + status detail ---
branch=""
git_extra=""
if [ -d "${dir}/.git" ] || git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  staged=$(git -C "$dir" diff --cached --name-only 2>/dev/null | grep -c .)
  modified=$(git -C "$dir" diff --name-only 2>/dev/null | grep -c .)
  untracked=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | grep -c .)
  ab=$(git -C "$dir" rev-list --left-right --count "@{upstream}...HEAD" 2>/dev/null)
  behind=$(printf '%s' "$ab" | cut -f1)
  ahead=$(printf '%s' "$ab" | cut -f2)
  [ "${staged:-0}" -gt 0 ]    2>/dev/null && git_extra="${git_extra} ${C_GREEN}+${staged}${R}"
  [ "${modified:-0}" -gt 0 ]  2>/dev/null && git_extra="${git_extra} ${C_AMBER}${G_MOD}${modified}${R}"
  [ "${untracked:-0}" -gt 0 ] 2>/dev/null && git_extra="${git_extra} ${C_GREY}?${untracked}${R}"
  [ "${ahead:-0}" -gt 0 ]     2>/dev/null && git_extra="${git_extra} ${C_GREEN}${G_UP}${ahead}${R}"
  [ "${behind:-0}" -gt 0 ]    2>/dev/null && git_extra="${git_extra} ${C_RED}${G_DOWN}${behind}${R}"
fi

# --- cost / duration ---
cost=$(J '.cost.total_cost_usd // empty')
wall_ms=$(J '.cost.total_duration_ms // empty')
api_ms=$(J '.cost.total_api_duration_ms // empty')

# --- in/out tokens from transcript (cached by mtime+size) ---
sid=$(J '.session_id // "x"')
tp=$(J '.transcript_path // ""'); tp=$(printf '%s' "$tp" | tr '\\' '/')
TOK_CACHE="/tmp/.claude_tokcache_${sid}"
TOK_BASE="/tmp/.claude_tokbase_${sid}"
TOK_REQ="/tmp/.claude_tokmark_req"
tin=""; tout=""; tcr=""
if [ -n "$tp" ] && [ -f "$tp" ]; then
  sig=$(stat -c '%Y-%s' "$tp" 2>/dev/null)
  if [ -f "$TOK_CACHE" ] && [ "$(sed -n '1p' "$TOK_CACHE" 2>/dev/null)" = "$sig" ]; then
    tin=$(sed -n '2p' "$TOK_CACHE"); tout=$(sed -n '3p' "$TOK_CACHE"); tcr=$(sed -n '4p' "$TOK_CACHE")
  else
    vals=$(grep '"usage"' "$tp" | jq -rs 'reduce .[] as $m ({i:0,o:0,r:0};
        .i += ($m.message.usage.input_tokens // 0)
      | .o += ($m.message.usage.output_tokens // 0)
      | .r += ($m.message.usage.cache_read_input_tokens // 0)) | "\(.i) \(.o) \(.r)"' 2>/dev/null)
    tin=$(printf '%s' "$vals" | cut -d' ' -f1)
    tout=$(printf '%s' "$vals" | cut -d' ' -f2)
    tcr=$(printf '%s' "$vals" | cut -d' ' -f3)
    [ -n "$tin" ] && printf '%s\n%s\n%s\n%s\n' "$sig" "$tin" "$tout" "$tcr" > "$TOK_CACHE"
  fi
fi

# marker: snapshot baseline on request, then show delta if a baseline exists
if [ -f "$TOK_REQ" ] && [ -n "$tin" ]; then
  printf '%s\n%s\n%s\n' "$tin" "$tout" "$tcr" > "$TOK_BASE"
  rm -f "$TOK_REQ"
fi
tok_mode=""; d_in=0; d_out=0
if [ -n "$tin" ]; then
  if [ -f "$TOK_BASE" ]; then
    b_in=$(sed -n '1p' "$TOK_BASE"); b_out=$(sed -n '2p' "$TOK_BASE")
    d_in=$(( tin - ${b_in:-0} )); d_out=$(( tout - ${b_out:-0} ))
    [ "$d_in" -lt 0 ] && d_in=0; [ "$d_out" -lt 0 ] && d_out=0
    tok_mode="delta"
  else
    tok_mode="cumulative"
  fi
fi

# --- rate limits (from stdin; resets_at is a unix epoch) ---
rl5_pct=$(J '.rate_limits.five_hour.used_percentage // empty')
rl5_reset=$(J '.rate_limits.five_hour.resets_at // empty')
rl7_pct=$(J '.rate_limits.seven_day.used_percentage // empty')
rl7_reset=$(J '.rate_limits.seven_day.resets_at // empty')

delta_epoch() {
  [ -z "$1" ] && return
  now=$(date -u +%s); d=$(( $1 - now ))
  [ "$d" -le 0 ] && { echo now; return; }
  dd=$(( d / 86400 )); hh=$(( (d % 86400) / 3600 )); mm=$(( (d % 3600) / 60 ))
  if   [ "$dd" -gt 0 ]; then echo "${dd}d ${hh}h"
  elif [ "$hh" -gt 0 ]; then echo "${hh}h ${mm}m"
  else echo "${mm}m"; fi
}

# --- context window ---
used=$(J '.context_window.used_percentage // empty')
exceeds=$(J '.exceeds_200k_tokens // false')
ctx_used=$(J '(.context_window.current_usage.cache_read_input_tokens + .context_window.current_usage.cache_creation_input_tokens + .context_window.current_usage.input_tokens + .context_window.current_usage.output_tokens) // empty')
ctx_total=$(J '.context_window.context_window_size // empty')

# ============================== render ==============================

# line 1: model [glyphs] | folder [• branch + git]
printf "%b%s%b" "$C_MODEL" "$model" "$R"
[ -n "$glyphs" ] && printf "%b" "$glyphs"
printf "%b" "$PIPE"
printf "%b%s%b" "$C_DIR" "$dir_name" "$R"
if [ -n "$branch" ]; then
  printf "%b" "$SEP"
  printf "%b%s%b" "$C_BRANCH" "$branch" "$R"
  [ -n "$git_extra" ] && printf "%b" "$git_extra"
fi

# line 2: cost | tokens (Δ since marker, else cumulative) | duration
printf "\n"
seg=0
if [ -n "$cost" ]; then
  printf "%b\$%.2f%b" "$C_GREY" "$cost" "$R"; seg=1
fi
if [ "$tok_mode" = "delta" ]; then
  [ "$seg" -eq 1 ] && printf "%b" "$PIPE"
  printf "%b%b in %b" "$C_DIM" "$G_DELTA" "$R"
  printf "%b%s%b" "$C_GREY" "$(commafy "$d_in")" "$R"
  printf "%b %b out %b" "$C_DIM" "$G_BULLET" "$R"
  printf "%b%s%b" "$C_GREEN" "$(commafy "$d_out")" "$R"
  seg=1
elif [ "$tok_mode" = "cumulative" ]; then
  [ "$seg" -eq 1 ] && printf "%b" "$PIPE"
  printf "%bin %b" "$C_DIM" "$R"
  printf "%b%s%b" "$C_GREY" "$(fmt_tok "$tin")" "$R"
  printf "%b %b out %b" "$C_DIM" "$G_BULLET" "$R"
  printf "%b%s%b" "$C_GREEN" "$(fmt_tok "$tout")" "$R"
  seg=1
fi

# line 3: 5h | 7d | ctx | duration
printf "\n"
seg=0
if [ -n "$rl5_pct" ]; then
  printf "%b5h %s%%%b" "$C_GREY" "$rl5_pct" "$R"
  r=$(delta_epoch "$rl5_reset"); [ -n "$r" ] && printf " %b(%s)%b" "$C_DIM" "$r" "$R"
  seg=1
fi
if [ -n "$rl7_pct" ]; then
  [ "$seg" -eq 1 ] && printf "%b" "$SEP"
  printf "%b7d %s%%%b" "$C_GREY" "$rl7_pct" "$R"
  r=$(delta_epoch "$rl7_reset"); [ -n "$r" ] && printf " %b(%s)%b" "$C_DIM" "$r" "$R"
  seg=1
fi
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  ctx_color="$C_GREY"
  if [ "$exceeds" = "true" ] || [ "$used_int" -ge 90 ]; then ctx_color="$C_RED"
  elif [ "$used_int" -ge 80 ]; then ctx_color="$C_AMBER"; fi
  [ "$seg" -eq 1 ] && printf "%b" "$PIPE"
  printf "%bctx %s%%%b" "$ctx_color" "$used_int" "$R"
  if [ -n "$ctx_used" ] && [ -n "$ctx_total" ]; then
    printf " %b(%sk/%sk)%b" "$C_DIM" "$(( ctx_used / 1000 ))" "$(( ctx_total / 1000 ))" "$R"
  fi
  seg=1
fi
if [ -n "$wall_ms" ]; then
  [ "$seg" -eq 1 ] && printf "%b" "$PIPE"
  printf "%b%s%b" "$C_GREY" "$(fmt_dur "$wall_ms")" "$R"
  [ -n "$api_ms" ] && printf " %b(%s api)%b" "$C_DIM" "$(fmt_dur "$api_ms")" "$R"
fi
