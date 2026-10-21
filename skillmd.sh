#!/data/data/com.termux/files/usr/bin/sh
# skillmd.sh — SKILL.md-compatible skill loader for Termux/Android
# Single file, zero dependencies (POSIX sh + awk/sed/grep only).
# Part of the 648 plan. Upstream of nano-mcp-termux (486 plan):
#   skill loading (this file) -> tool execution (nano-mcp-termux)
#
# Implements the SKILL.md three-layer progressive disclosure:
#   discovery  : `list` / `catalog`  — name+description only (~80-100 tok/skill)
#   activation : `show <skill>`      — full SKILL.md body on demand
#   execution  : `call`              — parse XML tool calls emitted by the model
#
# Usage:
#   skillmd.sh list                  list skills (human readable)
#   skillmd.sh catalog               catalog wrapped for system-prompt injection
#   skillmd.sh show <skill>          print full SKILL.md of one skill
#   skillmd.sh call [--file F]       extract+parse XML tool calls from stdin/file
#   skillmd.sh verify                sanity-check frontmatter of all skills
#   skillmd.sh count                 print catalog token estimate (chars/4)

set -u
SKILLS_DIR="${SKILLMD_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/skills}"

die() { echo "skillmd: $*" >&2; exit 1; }

# ---------- frontmatter helpers ----------

# print frontmatter body (between first and second '---' line)
fm_of() {
  awk '/^---[ \t]*$/{c++; next} c==1{print} c>=2{exit}' "$1"
}

fm_field() { # $1=file $2=field
  fm_of "$1" | sed -n "s/^$2:[ \t]*//p" | head -n 1
}

# ---------- discovery layer ----------

cmd_list() {
  [ -d "$SKILLS_DIR" ] || die "skills dir not found: $SKILLS_DIR"
  for d in "$SKILLS_DIR"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name=$(fm_field "$d/SKILL.md" name)
    desc=$(fm_field "$d/SKILL.md" description)
    printf '%s\n  %s\n' "${name:-$(basename "$d")}" "${desc:-<no description>}"
  done
}

cmd_catalog() {
  cat <<'EOF'
You can use the following skills. If a user request matches one, follow its instructions exactly and reply with the XML tool call it specifies.

<available_skills>
EOF
  for d in "$SKILLS_DIR"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name=$(fm_field "$d/SKILL.md" name)
    desc=$(fm_field "$d/SKILL.md" description)
    [ -n "$name" ] || name=$(basename "$d")
    printf -- '- %s: %s\n' "$name" "$desc"
  done
  cat <<'EOF'
</available_skills>
EOF
}

cmd_count() {
  n=$(cmd_catalog | wc -c)
  echo "catalog_chars=$n approx_tokens=$((n / 4))"
}

# ---------- activation layer ----------

cmd_show() {
  [ -n "${1:-}" ] || die "usage: skillmd.sh show <skill>"
  f="$SKILLS_DIR/$1/SKILL.md"
  [ -f "$f" ] || die "skill not found: $1"
  cat "$f"
}

# ---------- execution layer: XML tool-call parser ----------

# Reads model output; prints structured lines:
#   FUNC <name>
#   PARAM <key>=<value>
# Exit 0 if at least one well-formed <function> block was parsed, else 1.
parse_calls() {
  awk '
    BEGIN { RS = "</function>" ; found = 0 }
    {
      if (match($0, /<function[ \t]+name="[^"]*"/)) {
        head = substr($0, RSTART, RLENGTH)
        fn = head
        sub(/^.*name="/, "", fn)
        sub(/".*$/, "", fn)
        if (fn == "") next
        body = substr($0, RSTART + RLENGTH)
        out = "FUNC " fn "\n"
        nparsed = 0
        while (match(body, /<param[ \t]+name="[^"]*"[ \t]*>/)) {
          tag  = substr(body, RSTART, RLENGTH)
          rest = substr(body, RSTART + RLENGTH)
          close_at = index(rest, "</param>")
          if (close_at == 0) break
          k = tag; sub(/^.*name="/, "", k); sub(/".*$/, "", k)
          v = substr(rest, 1, close_at - 1)
          # Single-line values pass through verbatim (byte-stable).
          # Multi-line values are escaped so the one-line PARAM protocol holds.
          if (index(v, "\n") > 0) {
            esc = ""
            for (i = 1; i <= length(v); i++) {
              c = substr(v, i, 1)
              if      (c == "\\") esc = esc "\\\\"
              else if (c == "\n") esc = esc "\\n"
              else if (c == "\r") esc = esc "\\r"
              else                esc = esc c
            }
            v = esc
          }
          out = out "PARAM " k "=" v "\n"
          nparsed++
          body = substr(rest, close_at + 8)
        }
        # count attempted params: parsed + any param tags left in the unconsumed
        # remainder. Counting only the remainder avoids miscounting a literal
        # "<param" that appears *inside* an already-parsed value.
        # Any mismatch => malformed block, reject whole.
        attempted = nparsed; tmp = body
        while (match(tmp, /<param[ \t>\/]/)) { attempted++; tmp = substr(tmp, RSTART + RLENGTH) }
        if (attempted != nparsed) next
        printf "%s", out
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

cmd_call() {
  src=""
  if [ "${1:-}" = "--file" ]; then
    [ -n "${2:-}" ] || die "--file needs an argument"
    src="$2"
  fi
  if [ -n "$src" ]; then
    parse_calls < "$src"
  else
    parse_calls
  fi
}

# ---------- verify ----------

cmd_verify() {
  fail=0
  for d in "$SKILLS_DIR"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    s=$(basename "$d")
    f="$d/SKILL.md"
    ok=1
    fm_of "$f" | grep -q '^name:' || { echo "FAIL $s: missing name"; ok=0; }
    fm_of "$f" | grep -q '^description:' || { echo "FAIL $s: missing description"; ok=0; }
    grep -q '<function name=' "$f" || { echo "FAIL $s: no tool-call template"; ok=0; }
    [ "$ok" = 1 ] && echo "OK   $s" || fail=1
  done
  return $fail
}

# ---------- dispatch ----------

case "${1:-}" in
  list)    shift; cmd_list "$@" ;;
  catalog) shift; cmd_catalog "$@" ;;
  count)   shift; cmd_count "$@" ;;
  show)    shift; cmd_show "$@" ;;
  call)    shift; cmd_call "$@" ;;
  verify)  shift; cmd_verify "$@" ;;
  *) sed -n '2,20p' "$0" ;;
esac