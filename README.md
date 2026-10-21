# skillmd.sh — a single-file SKILL.md loader for Termux
[![CI](https://github.com/Lmeng486/skillmd-termux/actions/workflows/ci.yml/badge.svg)](https://github.com/Lmeng486/skillmd-termux/actions/workflows/ci.yml)


One POSIX-sh file, zero dependencies (`sh` + `awk`/`sed`/`grep` only), that loads
[SKILL.md](https://agentskills.io) skills into any OpenAI-compatible chat endpoint
on an Android phone — no root, no Node, no Python runtime needed for the loader itself.

Part of the 648 plan. Upstream of [nano-mcp-termux](https://github.com/Lmeng486/nano-mcp-termux) (the 486 plan):
**skill loading (this file) → tool execution (nano-mcp-termux)** — together they form
a complete on-device agent loop: SKILL.md decides *what to do*, MCP tools execute *how*.

## What it does

Implements the SKILL.md three-level progressive disclosure with three commands:

| Level | Command | What the model sees | Token cost |
|---|---|---|---|
| Discovery | `list` / `catalog` / `count` | skill names + descriptions only | ~80 tok/skill (measured: 923 chars ≈ 230 tok for 3 skills) |
| Activation | `show <skill>` | the full SKILL.md body | on demand |
| Execution | `call [--file F]` | parses the model's XML tool call, prints `FUNC`/`PARAM` records | — |

`catalog` prints the system-prompt block to inject; `call` is the strict exit-code
gate: exit 0 = a well-formed XML tool call was found (`FUNC name` + `PARAM k=v`
records), exit 1 = plain prose (no call). Malformed blocks are rejected whole —
if the number of parsed params doesn't match the attempted ones, the block is discarded.

## Quick start (inside Termux)

```sh
./skillmd.sh list                 # discovery: names + descriptions
./skillmd.sh catalog              # the system-prompt block to inject
./skillmd.sh show word-count      # activation: full SKILL.md
printf '<function name="word-count">\n<param name="text">hello world</param>\n</function>\n' > call.out
./skillmd.sh call --file call.out # execution: FUNC word-count / PARAM text=hello world
./skillmd.sh verify               # check every skill has name/description/tool-call template
```

Skills are discovered from `skills/` next to the script (override with `SKILLMD_DIR`).
Each skill is a directory with a `SKILL.md` (YAML frontmatter: `name`, `description`,
then the body that tells the model exactly which XML tool call to emit). Three worked
examples ship in `skills/`: `word-count`, `text-reverse`, `base64-encode`.

## Measure it yourself

`run_tests.sh` is the harness that produced the quantization-decay numbers — it drives
a local `llama-server` with the catalog as system prompt, saves every raw model output,
parses each with `skillmd.sh call`, and judges trigger/parse/fill per case:

```sh
llama-server -m Q4_K_M.gguf --host 127.0.0.1 --port 8080 -c 4096 -t 7 &
TAG=q4km REPEATS=3 MAXTOK=384 sh run_tests.sh   # full 12-case set × 3 repeats
python3 posthoc.py results/results_q4km.tsv results/ q4km   # post-hoc trigger_ok recompute
```

`cases.tsv` holds the 12 cases (3 skills × 3 phrasings + 3 negatives);
`SERVER`, `TAG`, `REPEATS`, `MAXTOK` are all environment-overridable.

The full measured story — Q4_K_M vs Q8_0 trigger rates, the EMPTY_THINKING
token-budget attribution, and the "smaller quant + bigger budget" conclusion —
lives in the companion report:
[Quantization Decay, Measured](https://github.com/Lmeng486/awesome-termux-mcp/blob/main/docs/QUANT-DECAY-MINICPM5.md).

The upstream discussion thread for those numbers — raw tables, the maintainer-facing summary, and follow-ups — is [OpenBMB/MiniCPM#388](https://github.com/OpenBMB/MiniCPM/issues/388).

## Parser fix in v1.0.1

The original `parse_calls` regex matched param values with `[^<]*`, which made two
classes of *valid* model output fail:

1. **A `<` inside a value was fatal.** `<param name="text">if a < b then</param>`
   rejected the entire block (exit 1), because `[^<]*` cannot cross the `<`.
2. **Multi-line values broke the line protocol.** A value spanning lines emitted
   `PARAM body=line1` followed by a bare `line2`, so downstream consumers could not
   tell where the record ended.

Both are fixed by scanning for the `<param name="…">` open tag and then using
`index()` to find its matching `</param>`, instead of matching the value with a
character class. Values containing `<`, `>`, or full HTML tags now pass through
verbatim; multi-line values are escaped (`\n`, `\r`, `\\`) so every `PARAM` stays
exactly one line. The whole-block rejection rule is unchanged: a block is still
discarded if the parsed param count does not match the attempted count.

### Backward compatibility, proven on real data

The fix was regression-tested against **118 raw model outputs** captured by
`run_tests.sh` during the quantization measurements (Q4_K_M, Q4_V512, Q8_K_M runs
plus the mixed `all_outs` set). Old and new parsers were run over all 118 files and
compared byte-for-byte on stdout, exit code, and line count:

```
samples: 118
OLD: success(exit=0)=65  fail(exit=1)=53
NEW: success(exit=0)=65  fail(exit=1)=53
diff old.txt new.txt  →  no output (zero differences)
```

So the published numbers did not move: **no captured output contained a `<function`
block that the `<` bug was rejecting** (0 such cases were found). The fix is a
strictly additive widening — it accepts inputs that were previously rejected, and
changes nothing that already worked. The measured 65/53 split, and therefore every
trigger/parse rate in the companion report, stands as published.

`tests/parser_test.sh` pins this behaviour with 19 cases (happy path, `<`/`>`/HTML/
backslash/multi-line values, and the rejection paths) and runs in CI. Run against
the previous parser, 4 of the 19 fail (`extra ws in attrs`, `lt in value`,
`html tag in value`, `multiline value`); all 19 pass after the fix.

## Why one file, zero dependencies

Same design rule as nano-mcp-termux: on a phone, install friction is the enemy.
`sh` + `awk` are already in every Termux install; a 177-line file can be read
in one sitting, audited, and pasted anywhere — including into an `adb shell`.

## Note
Not affiliated with `skillmds/skillmd` (a CLI for managing skill files) —
this is a runtime loader that injects SKILL.md into OpenAI-compatible
endpoints.

## License
MIT — see [LICENSE](LICENSE).
