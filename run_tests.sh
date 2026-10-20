#!/data/data/com.termux/files/usr/bin/sh
# run_tests.sh — 648 plan quantization-decay harness (zero-dep: sh+awk+curl)
# Drives llama-server /v1/chat/completions with the skill catalog as system
# prompt, saves raw outputs, parses them with skillmd.sh, judges:
#   parse_ok   = skillmd.sh call exited 0 (well-formed XML tool call found)
#   trigger_ok = FUNC matches expected tool (or no call for NONE cases)
#   filled_ok  = params present and not literal placeholders
# Usage: TAG=q4km REPEATS=3 sh run_tests.sh
set -u
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVER="${SERVER:-http://127.0.0.1:8080}"
TAG="${TAG:-q4km}"
REPEATS="${REPEATS:-3}"
MAXTOK="${MAXTOK:-256}"
CASES="$DIR/cases.tsv"
OUT="$DIR/results"
mkdir -p "$OUT"
RESULTS="$OUT/results_$TAG.tsv"

json_escape() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk '{printf "%s\\n", $0}' | sed 's/\\n$//'
}

# extract "content" value from a chat-completions JSON response (state machine)
extract_content() {
  awk '
    { buf = buf $0 "\n" }
    END {
      key = "\"content\":\""
      i = index(buf, key)
      if (i == 0) { print "EXTRACT_FAIL" > "/dev/stderr"; exit 9 }
      i += length(key); out = ""
      while (i <= length(buf)) {
        c = substr(buf, i, 1)
        if (c == "\\") {
          nxt = substr(buf, i+1, 1)
          if (nxt == "n") out = out "\n"
          else if (nxt == "t") out = out "\t"
          else if (nxt == "r") out = out "\r"
          else out = out nxt
          i += 2; continue
        }
        if (c == "\"") break
        out = out c; i++
      }
      printf "%s", out
    }
  ' "$1"
}

CATALOG=$("$DIR/skillmd.sh" catalog) || { echo "catalog failed"; exit 1; }
CESC=$(printf '%s\n' "$CATALOG" | json_escape)

echo "tag	case	rep	expected	func_seen	parse_ok	trigger_ok	filled_ok	secs" > "$RESULTS"

case_no=0
while IFS="$(printf '\t')" read -r cid expected prompt; do
  [ -n "${cid:-}" ] || continue
  case_no=$((case_no+1))
  PESC=$(printf '%s' "$prompt" | json_escape)
  rep=1
  while [ "$rep" -le "$REPEATS" ]; do
    payload=$(printf '{"model":"local","messages":[{"role":"system","content":"%s"},{"role":"user","content":"%s"}],"max_tokens":%s,"temperature":1.0,"top_p":0.95,"min_p":0.0}' "$CESC" "$PESC" "$MAXTOK")
    t0=$(date +%s)
    curl -s -m 180 "$SERVER/v1/chat/completions" -H 'Content-Type: application/json' -d "$payload" > "$OUT/resp.json" 2>/dev/null
    curl_rc=$?
    t1=$(date +%s)
    secs=$((t1 - t0))
    if [ "$curl_rc" -ne 0 ]; then
      echo "$TAG	$cid	$rep	$expected	CURL_ERR	0	0	0	$secs" >> "$RESULTS"
      rep=$((rep+1)); continue
    fi
    if extract_content "$OUT/resp.json" > "$OUT/${TAG}_${cid}_${rep}.out" 2>/dev/null; then
      if "$DIR/skillmd.sh" call --file "$OUT/${TAG}_${cid}_${rep}.out" > "$OUT/${TAG}_${cid}_${rep}.parsed" 2>/dev/null; then
        parse_ok=1
      else
        parse_ok=0
      fi
      func_seen=$(awk '$1=="FUNC"{print $2; exit}' "$OUT/${TAG}_${cid}_${rep}.parsed" 2>/dev/null)
      if [ "$expected" = "NONE" ]; then
        if [ -z "$func_seen" ]; then trigger_ok=1; else trigger_ok=0; fi
      else
        if [ "$func_seen" = "$expected" ]; then trigger_ok=1; else trigger_ok=0; fi
      fi
      if [ "$parse_ok" = 1 ] \
         && grep -q '^PARAM ' "$OUT/${TAG}_${cid}_${rep}.parsed" \
         && ! grep -qE '^PARAM .*=(CHARACTER_COUNT|WORD_COUNT|LINE_COUNT|REVERSED_STRING|BASE64_STRING)[^a-z_]*$' "$OUT/${TAG}_${cid}_${rep}.parsed"; then
        filled_ok=1
      else
        filled_ok=0
      fi
      echo "$TAG	$cid	$rep	$expected	${func_seen:-<none>}	$parse_ok	$trigger_ok	$filled_ok	$secs" >> "$RESULTS"
    else
      echo "$TAG	$cid	$rep	$expected	EXTRACT_FAIL	0	0	0	$secs" >> "$RESULTS"
    fi
    rep=$((rep+1))
  done
done < "$CASES"

echo "=== AGGREGATE ($TAG) ==="
awk -F'\t' 'NR>1 {
  n[$1]++; tp[$1]+=$7; pp[$1]+=$6; fp[$1]+=$8
  key=$1"_"$4; kn[key]++; kt[key]+=$7
  if ($4!="NONE") { tn[key]++; tt[key]+=$7 }
}
END {
  for (t in n) printf "MODEL %s trigger=%d/%d (%.1f%%) parse=%d/%d (%.1f%%) filled=%d/%d (%.1f%%)\n", t, tp[t], n[t], 100*tp[t]/n[t], pp[t], n[t], 100*pp[t]/n[t], fp[t], n[t], 100*fp[t]/n[t]
  for (k in kn) if (k !~ /NONE$/) printf "  TOOL %s trigger=%d/%d (%.1f%%)\n", k, tt[k], tn[k], 100*tt[k]/tn[k]
  for (k in kn) if (k ~ /NONE$/) printf "  ABSTAIN %s correct=%d/%d\n", k, kt[k], kn[k]
}' "$RESULTS"
echo "RESULTS_FILE=$RESULTS"