#!/bin/sh
input=$(cat)

# ---- colors ----
DIM=$(printf '\033[2m');    RST=$(printf '\033[0m');    GRY=$(printf '\033[90m')
GRN=$(printf '\033[32m');   RED=$(printf '\033[31m');   BLD=$(printf '\033[1m')
CYN=$(printf '\033[36m');   MGN=$(printf '\033[35m');   YLW=$(printf '\033[33m')

# ---- 5h + 7d rate-limit bar (Pro/Max only, after first API response) ----
pct=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
resets=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
pct7d=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
bar=""
if [ -n "$pct" ] && [ -n "$resets" ]; then
  reset_time=$(date -r "$resets" "+%H:%M" 2>/dev/null || date -d "@$resets" "+%H:%M" 2>/dev/null)
  pctint=$(printf '%.0f' "$pct")
  width=12
  filled=$(awk -v p="$pct" -v w="$width" 'BEGIN{f=int(p/100*w+0.5); if(f>w)f=w; if(f<0)f=0; print f}')
  # color by usage: <70 green, 70-90 yellow, >=90 red
  color=$(awk -v p="$pct" 'BEGIN{print (p>=90)?31:((p>=70)?33:32)}')
  CLR=$(printf '\033[1;%sm' "$color")
  fb=""; eb=""; i=0
  while [ "$i" -lt "$filled" ]; do fb="${fb}█"; i=$((i+1)); done
  while [ "$i" -lt "$width" ];  do eb="${eb}░"; i=$((i+1)); done
  # combine 5h and 7d percentages if 7d is available
  if [ -n "$pct7d" ]; then
    pct7dint=$(printf '%.0f' "$pct7d")
    color7d=$(awk -v p="$pct7d" 'BEGIN{print (p>=90)?31:((p>=70)?33:32)}')
    CLR7D=$(printf '\033[1;%sm' "$color7d")
    rate_str="${CLR}${pctint}%${RST} ${GRY}/${RST} ${CLR7D}${pct7dint}%${RST}"
  else
    rate_str="${CLR}${pctint}%${RST}"
  fi
  bar="${GRY}▕${CLR}${fb}${GRY}${eb}▏${RST} ${rate_str}  ${DIM}↻ ${reset_time}${RST}"
fi

# ---- row 1: diff + model + effort + context ----
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty'); effort=${effort:--}
added=$(printf '%s' "$input" | jq -r '.cost.total_lines_added // 0')
removed=$(printf '%s' "$input" | jq -r '.cost.total_lines_removed // 0')
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
ctx_used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')

info="${GRN}↑${added}${RST} ${RED}↓${removed}${RST}  ${DIM}·${RST}  ${GRY}${model}${RST}  ${DIM}|${RST}  ${GRY}${effort}${RST}"
if [ -n "$ctx_used" ]; then
  ctx_int=$(printf '%.0f' "$ctx_used")
  ctx_color=$(awk -v p="$ctx_used" 'BEGIN{print (p>=90)?31:((p>=70)?33:32)}')
  CTX_CLR=$(printf '\033[%sm' "$ctx_color")
  info="${info}  ${DIM}·${RST}  ${DIM}ctx${RST} ${CTX_CLR}${ctx_int}%${RST}"
fi

# ---- row 2: cwd + repo ----
repo=$(printf '%s' "$input" | jq -r '.workspace.repo | if . then .owner + "/" + .name else empty end')
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')

# shorten home dir to ~
home="$HOME"
case "$cwd" in
  "$home"*) cwd="~${cwd#$home}" ;;
esac

# styled directory: dim parent path, bold basename
cwd_dir=$(dirname "$cwd")
cwd_base=$(basename "$cwd")
if [ "$cwd_dir" = "." ] || [ "$cwd_dir" = "~" ] || [ "$cwd_dir" = "/" ]; then
  cwd_styled="${CYN}${BLD}${cwd_base}${RST}"
else
  cwd_styled="${DIM}${cwd_dir}/${RST}${CYN}${BLD}${cwd_base}${RST}"
fi

row2="${GRY}❯${RST} ${cwd_styled}"
if [ -n "$repo" ]; then
  row2="${row2}  ${DIM}on${RST}  ${MGN}${BLD}${repo}${RST}"
fi

# ---- output ----
if [ -n "$bar" ]; then
  printf '%s  %s·%s  %s\n%s' "$bar" "$DIM" "$RST" "$info" "$row2"
else
  printf '%s\n%s' "$info" "$row2"
fi
