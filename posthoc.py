#!/usr/bin/env python3
# posthoc.py — 648 plan post-hoc rescoring (fixes scenario-name vs skill-name mapping)
# Reads results TSV + raw .out files, recomputes trigger_ok with correct mapping,
# classifies failure modes, computes timing stats.
import sys, os, glob

SCENARIO2SKILL = {
    'word_count_report': 'word-count',
    'reverse_report': 'text-reverse',
    'b64_report': 'base64-encode',
}

def classify_failure(out_path):
    """Classify why a positive-case response failed to parse."""
    try:
        raw = open(out_path, encoding='utf-8', errors='replace').read()
    except OSError:
        return 'NO_FILE'
    s = raw.strip()
    if not s:
        return 'EMPTY_THINKING'      # all tokens burned in reasoning_content
    if '"role":"tool_call"' in s or "'role':'tool_call'" in s:
        return 'FORMAT_DRIFT_JSON'   # JSON-style tool call instead of XML
    if '<function' in s and '</function>' not in s:
        return 'TRUNCATED_XML'       # started XML but got cut
    if '<function' in s:
        return 'MALFORMED_XML'       # XML present but params malformed
    return 'NO_TOOL_CALL'            # plain prose answer, no call attempt

def main(results_tsv, outdir, tag):
    rows = []
    with open(results_tsv, encoding='utf-8') as f:
        header = f.readline().rstrip('\n').split('\t')
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) != len(header):
                continue
            rows.append(dict(zip(header, parts)))

    pos = [r for r in rows if r['expected'] != 'NONE']
    neg = [r for r in rows if r['expected'] == 'NONE']

    # corrected trigger
    for r in rows:
        if r['expected'] == 'NONE':
            r['trigger_fix'] = 1 if r['func_seen'] == '<none>' else 0
        else:
            skill = SCENARIO2SKILL.get(r['expected'], r['expected'])
            r['trigger_fix'] = 1 if r['func_seen'] == skill else 0

    n_pos, n_neg = len(pos), len(neg)
    trig = sum(int(r['trigger_fix']) for r in pos)
    abstain = sum(int(r['trigger_fix']) for r in neg)
    # parse_ok among positives that produced any output
    produced = [r for r in pos if r['func_seen'] != '<none>']
    parse_prod = sum(int(r['parse_ok']) for r in produced)
    filled = sum(int(r['filled_ok']) for r in produced)

    # failure taxonomy on positives with parse_ok=0
    taxo = {}
    for r in pos:
        if int(r['parse_ok']) == 0:
            f = os.path.join(outdir, f"{tag}_{r['case']}_{r['rep']}.out")
            m = classify_failure(f)
            taxo[m] = taxo.get(m, 0) + 1

    # timing
    secs = [int(r['secs']) for r in rows]
    pos_secs = [int(r['secs']) for r in pos]
    neg_secs = [int(r['secs']) for r in neg]

    print(f"=== POST-HOC RESCORE ({tag}) ===")
    print(f"positives: {n_pos}  negatives: {n_neg}")
    print(f"trigger_rate (corrected): {trig}/{n_pos} = {100*trig/n_pos:.1f}%")
    print(f"abstain_correct (negatives): {abstain}/{n_neg} = {100*abstain/n_neg:.1f}%")
    print(f"parse_rate (among {len(produced)} outputs): {parse_prod}/{len(produced)} = {100*parse_prod/len(produced):.1f}%" if produced else "parse_rate: n/a")
    print(f"filled_rate (among parsed): {filled}/{parse_prod} = {100*filled/parse_prod:.1f}%" if parse_prod else "filled_rate: n/a")
    print(f"failure_taxonomy (positives, parse_ok=0):")
    for k in sorted(taxo):
        print(f"  {k}: {taxo[k]}")
    print(f"timing: all mean={sum(secs)/len(secs):.1f}s  pos_mean={sum(pos_secs)/len(pos_secs):.1f}s  neg_mean={sum(neg_secs)/len(neg_secs):.1f}s")

    # per-skill breakdown
    print("per-skill trigger (corrected):")
    for sk in set(SCENARIO2SKILL.values()):
        sub = [r for r in pos if SCENARIO2SKILL.get(r['expected']) == sk]
        t = sum(int(r['trigger_fix']) for r in sub)
        print(f"  {sk}: {t}/{len(sub)} = {100*t/len(sub):.1f}%")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
