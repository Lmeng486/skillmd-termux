#!/bin/sh
# skillmd.sh parser test suite (POSIX sh)
# Usage: sh tests/parser_test.sh [path-to-skillmd.sh]

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname -- "$SCRIPT_DIR")
SMD="${1:-$ROOT/skillmd.sh}"
[ -f "$SMD" ] || { echo "missing: $SMD" >&2; exit 2; }

pass=0
fail=0

# check NAME EXPECTED_EXIT INPUT [EXPECTED_OUTPUT_SUBSTRING]
check() {
  name=$1; exp=$2; input=$3; want=$4
  out=$(printf '%s' "$input" | sh "$SMD" call 2>&1)
  ec=$?
  st=PASS
  if [ "$ec" != "$exp" ]; then st=FAIL; fi
  if [ -n "$want" ]; then
    case $out in
      *"$want"*) : ;;
      *) st=FAIL ;;
    esac
  fi
  if [ "$st" = PASS ]; then pass=$((pass+1)); else
    fail=$((fail+1))
    printf 'FAIL %-30s exit=%s(exp %s) out=%s\n' "$name" "$ec" "$exp" "$out"
  fi
}

# ---- happy path ----
check 'basic call'            0 '<function name="word-count"><param name="text">hello world</param></function>' 'PARAM text=hello world'
check 'multi param'           0 '<function name="word-count"><param name="text">a</param><param name="n">1</param></function>' 'PARAM n=1'
check 'multi block'           0 '<function name="word-count"><param name="text">a</param></function><function name="text-reverse"><param name="text">b</param></function>' 'FUNC text-reverse'
check 'empty value'           0 '<function name="word-count"><param name="text"></param></function>' 'PARAM text='
check 'no params'             0 '<function name="word-count"></function>' 'FUNC word-count'
check 'extra ws in attrs'     0 '<function  name="word-count" ><param  name="text" >x</param></function>' 'PARAM text=x'
check 'unicode'               0 '<function name="word-count"><param name="text">你好世界</param></function>' 'PARAM text=你好世界'
check 'equals in value'       0 '<function name="word-count"><param name="text">a=b</param></function>' 'PARAM text=a=b'

# ---- regression: value containing < or > (was rejected before v1.0.1) ----
check 'lt in value'           0 '<function name="word-count"><param name="text">if a < b then</param></function>' 'PARAM text=if a < b then'
check 'gt in value'           0 '<function name="word-count"><param name="text">a > b</param></function>' 'PARAM text=a > b'
check 'html tag in value'     0 '<function name="word-count"><param name="text"><b>hi</b></param></function>' 'PARAM text=<b>hi</b>'
check 'backslash in value'    0 '<function name="word-count"><param name="text">a\b</param></function>' 'PARAM text=a\b'

# ---- regression: multi-line value must stay one line (escaped) ----
check 'multiline value'       0 '<function name="text-reverse"><param name="text">l1
l2</param></function>' 'PARAM text=l1\nl2'

# ---- rejection paths ----
check 'prose only'            1 'just some prose, no tool call'
check 'empty input'           1 ''
check 'unclosed function'     0 '<function name="word-count"><param name="text">x</param>' 'PARAM text=x'
check 'empty func name'       1 '<function name=""><param name="text">x</param></function>'
check 'unclosed param'        1 '<function name="word-count"><param name="text">x</function>'
check 'bare param tag'        1 '<function name="word-count"><param>x</param></function>'

printf 'parser_test: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
