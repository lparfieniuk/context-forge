# ContextForge Token Benchmarks

This directory stores baseline TSV snapshots used to track token efficiency across upgrade iterations.

## What it measures

Each baseline captures line count, word count, and estimated token count for every rule, skill, and agent in the plugin. Running comparisons between baselines shows whether upgrades reduced or increased context cost.

## How to run

```bash
# From plugin root
bash core/scripts/tools/benchmark-tokens.sh
```

## How to capture a baseline

```bash
bash core/scripts/tools/benchmark-tokens.sh --baseline
# Saves: core/benchmarks/baseline-YYYY-MM-DD.tsv
```

## How to compare against a baseline

```bash
bash core/scripts/tools/benchmark-tokens.sh --compare core/benchmarks/baseline-2026-04-26.tsv
```

The Delta column shows `+N` (token increase), `-N` (reduction), `0` (unchanged), or `NEW` (file did not exist in baseline).

## Token estimate formula

```
est_tokens = int(words * 1.3 + 0.5)
```

Words are counted with `wc -w`. The factor 1.3 approximates the GPT-style tokenizer ratio (roughly 0.75 words per token), rounded to nearest integer.

## Thresholds

Files exceeding the following line counts are flagged with a warning marker in the table:

- Rules: more than 120 lines
- Skills: more than 100 lines
- Agents: more than 100 lines

Files above threshold are not blocked — they are flagged for manual review during optimization passes.

## TSV format

Baseline files are tab-separated with a header row:

```
file    lines   words   est_tokens  date
```

Files are named `baseline-YYYY-MM-DD.tsv`. Multiple baselines can coexist; pass the specific file to `--compare`.
