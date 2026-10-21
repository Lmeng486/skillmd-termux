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

## Why one file, zero dependencies

Same design rule as nano-mcp-termux: on a phone, install friction is the enemy.
`sh` + `awk` are already in every Termux install; a 158-line file can be read
in one sitting, audited, and pasted anywhere — including into an `adb shell`.

## Note
Not affiliated with `skillmds/skillmd` (a CLI for managing skill files) —
this is a runtime loader that injects SKILL.md into OpenAI-compatible
endpoints.

## License
MIT — see [LICENSE](LICENSE).
