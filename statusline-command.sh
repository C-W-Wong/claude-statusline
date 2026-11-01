#!/bin/sh
# Claude Code status line. Responsive: Claude Code passes the terminal width as
# $COLUMNS on every run, and the layout adapts to it.
#
# Wide: 2 rows x 3 columns          gauges │ session │ workspace
#   ━━━━──────  41%   demo-session                  ~/Code/projects/my-app · owner/repo
#   ━━━━━━━━──  78%   Opus 5.5 · max   ↻ Sat 17:00   +1364 -23
#
# Medium: 3 rows x 2 columns        numbers │ names
#   ━━━━──────  41%   demo-session
#   ━━━━━━━━──  78%   Opus 5.5 · max   ↻ Sat 17:00
#   +1364 -23         ~/Code/projects/my-app · owner/repo
#
# Narrow: things give way in order: path → …/parent/dir, repo, effort, reset time;
# bars shrink to 5 cells, then to bare percentages; long names end in "…".
#
# Gauges: context used, then plan usage (the 5-hour window when there is one,
# weekly % after the slash; otherwise the weekly window). Green <70, yellow <90, red.
# Pair with "refreshInterval" in settings.json so a resize re-lays it out.
exec jq -j --arg cols "${COLUMNS:-0}" --arg home "$HOME" '
# ---- palette ----
def RST: "\u001b[0m";
def GRY: "\u001b[90m";              # secondary text
def FNT: "\u001b[38;5;240m";        # separators, empty track, zero counts
def BLD: "\u001b[1m";
def ORG: "\u001b[1;38;5;208m";      # OHM brand orange (bold): session name
def GRN: "\u001b[32m"; def YLW: "\u001b[33m"; def RED: "\u001b[31m";
def tone: if . >= 90 then RED elif . >= 70 then YLW else GRN end;

# ---- text ----
def rep($s; $n): [range(0; $n)] | map($s) | join("");
def txt: tostring | explode | map(select(. >= 32 and . != 127)) | implode;   # strip control chars
def pc: if type == "number" then . + 0.5 | floor else null end;               # round a percentage
def cw:                                         # terminal columns of one codepoint (CJK/emoji = 2)
  if (. >= 4352 and . <= 4447) or . == 9001 or . == 9002
     or (. >= 11904 and . <= 42191 and . != 12351) or (. >= 44032 and . <= 55203)
     or (. >= 63744 and . <= 64255) or (. >= 65040 and . <= 65049)
     or (. >= 65072 and . <= 65135) or (. >= 65280 and . <= 65376)
     or (. >= 65504 and . <= 65510) or (. >= 127744 and . <= 128591)
     or (. >= 129280 and . <= 129535) or (. >= 131072 and . <= 262141)
  then 2 else 1 end;
def dw: explode | map(cw) | add // 0;           # display width of a string
def fit($n):                                    # cut to $n columns, ending in …
  if dw <= $n then . elif $n < 1 then "" else
    reduce (explode | .[]) as $c ({w: 0, out: [], stop: false};
      if .stop then . else ($c | cw) as $k
        | if .w + $k < $n then .w += $k | .out += [$c] else .stop = true end end)
    | (.out | implode) + "…" end;

# ---- lines: arrays of {t: text, s: style} segments ----
def S($t; $s): {t: $t, s: $s};
def wid: map(.t | dw) | add // 0;
def padto($n): . + [S(rep(" "; $n - wid); "")];
def firstfit($n): map(select(wid <= $n)) | first;
def render: map(select(.t != "") | if .s == "" then .t else .s + .t + RST end) | join("");

# gauge for a percentage (. = number or null): $bw-cell bar + right-aligned %, or bare % when $bw is 0.
# Never empty above 0%, never full below 100%.
def gauge($bw):
  if . == null then [S(if $bw > 0 then rep("─"; $bw) + "   --" else "--" end; FNT)]
  else . as $p
    | (if $bw == 0 then 0 else (($p * $bw + 50) / 100 | floor)
         | if . >= $bw and $p < 100 then $bw - 1 elif . > $bw then $bw
           elif . == 0 and $p > 0 then 1 else . end end) as $f
    | ($p | tone) as $c
    | [S(rep("━"; $f); $c), S(rep("─"; $bw - $f); FNT),
       S(if $bw > 0 then " " + ("   \($p)%" | .[-4:]) else "\($p)%" end; $c)]
  end;

($cols | tonumber? // 0) as $C
| (if $C > 0 then $C - 4 else 1000 end) as $A    # usable width, leaving a little slack

# ---- data ----
| ((.session_name // "" | txt) as $s
   | if $s != "" then $s else ($ENV.CLAUDE_WINDOW_LABEL // "" | txt) end | fit(64)) as $name
| (.model.display_name // "" | txt) as $model
| (.effort.level // "" | txt) as $effort
| (.cost.total_lines_added   | if type == "number" then floor else 0 end) as $add
| (.cost.total_lines_removed | if type == "number" then floor else 0 end) as $del
| (.workspace.repo | if type == "object" then "\(.owner)/\(.name)" | txt else "" end) as $repo
| (.context_window.used_percentage | pc) as $ctx
| (.rate_limits.five_hour // {}) as $h5
| (.rate_limits.seven_day // {}) as $wk
| (if ($h5.used_percentage | type) == "number" and ($h5.resets_at | type) == "number"
   then {p: ($h5.used_percentage | pc), x: ($wk.used_percentage | pc),
         r: ($h5.resets_at | floor | strflocaltime("%H:%M"))}
   else {p: ($wk.used_percentage | pc), x: null,
         r: ($wk.resets_at | if type == "number" then floor | strflocaltime("%a %H:%M") else null end)}
   end) as $use

# ---- location: ~ for home; full parent, or short parent "…/dir/" ----
| (.workspace.current_dir // .cwd // "" | txt
   | if $home != "" and (. == $home or startswith($home + "/")) then "~" + .[($home | length):] else . end) as $cwd
| ($cwd | split("/")) as $parts
| (if $cwd == "/" then "/" else ($parts[-1] // "") end) as $base
| ($cwd[0:(($cwd | length) - ($base | length))]) as $par
| (if ($parts | length) > 3 then "…/" + $parts[-2] + "/" else $par end) as $short

# ---- building blocks ----
| [S("+\($add)"; if $add > 0 then GRN else FNT end), S(" "; ""),
   S("-\($del)"; if $del > 0 then RED else FNT end)] as $diff
| def ctxg($bw): $ctx | gauge($bw);
  def useg($bw; $x): ($use.p | gauge($bw))
    + (if $x and $use.x != null then [S(" / "; FNT), S("\($use.x)%"; $use.x | tone)] else [] end);
  def title($n): if $name == "" then [S("unnamed" | fit($n); GRY)] else [S($name | fit($n); ORG)] end;
  def model($eff; $gap):
    ([S($model; "")] | map(select(.t != ""))) as $m
    | ($m + (if $eff and $effort != "" then (if $m == [] then [] else [S(" · "; FNT)] end) + [S($effort; GRY)] else [] end)) as $me
    | $me + (if $gap != null and $use.r != null then (if $me == [] then [] else [S($gap; "")] end) + [S("↻ " + $use.r; GRY)] else [] end);
  def place($p; $withrepo): [S($p; GRY), S($base; BLD)]
    + (if $withrepo and $repo != "" then [S(" · "; FNT), S($repo; GRY)] else [] end);

# ---- wide: 2 rows x 3 columns, when everything fits at full detail ----
# (names over 40 columns would leave a big hole in row 2, so they get the 3-row layout)
  (ctxg(10)) as $g1 | (useg(10; true)) as $g2
| ([$g1, $g2] | map(wid) | max) as $lw
| title(1000) as $t | model(true; "   ") as $m
| ([$t, $m] | map(wid) | max) as $mw
| place($par; true) as $loc
| if $lw + 3 + $mw + 3 + ([$loc, $diff] | map(wid) | max) <= $A
     and ($t | wid) <= ([($m | wid), 40] | max) then
    [ ($g1 | padto($lw)) + [S("   "; "")] + ($t | padto($mw)) + [S("   "; "")] + $loc,
      ($g2 | padto($lw)) + [S("   "; "")] + ($m | padto($mw)) + [S("   "; "")] + $diff ]
  else
# ---- otherwise 3 rows x 2 columns; left column shrinks first when space is tight ----
    ([ {bw: 10, x: true, g: 3}, {bw: 5, x: true, g: 2}, {bw: 0, x: true, g: 2}, {bw: 0, x: false, g: 2} ]
     | map(. + {lw: ([ctxg(.bw), useg(.bw; .x), $diff] | map(wid) | max)})
     | (map(select($A - .lw - .g >= 24)) | first)            # first that leaves 24+ cols for names,
       // ((map(.lw + .g) | min) as $mn | map(select(.lw + .g == $mn)) | first)) as $o   # else the slimmest
    | ($A - $o.lw - $o.g) as $n
    | [S(rep(" "; $o.g); "")] as $gap
    | [ (ctxg($o.bw) | padto($o.lw)) + $gap + title($n),
        (useg($o.bw; $o.x) | padto($o.lw)) + $gap
          + ([model(true; "   "), model(true; "  "), model(false; "  "), model(false; null)]
             | firstfit($n) // [S($model | fit($n); "")]),
        ($diff | padto($o.lw)) + $gap
          + ([place($par; true), place($short; true), place($par; false), place($short; false), [S($base; BLD)]]
             | firstfit($n) // [S($base | fit($n); BLD)]) ]
  end
| map(render) | join("\n")
' 2>/dev/null
