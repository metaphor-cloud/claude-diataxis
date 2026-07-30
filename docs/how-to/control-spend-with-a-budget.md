---
title: "Control spend with a budget"
slug: how-to/control-spend-with-a-budget
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:40:36Z
frozen: false
---

# Control spend with a budget

Cap what a single `diataxis generate` run can spend, understand what happens when the ceiling is hit, and read back what was actually spent.

## Before you start

- tutorials/generate-your-first-documentation-set
- how-to/review-and-edit-the-page-plan

## Steps

1. Set a ceiling for this run with --budget-usd, or set budget_usd once in diataxis.config.json so every run is capped without repeating the flag.

   ```console
   diataxis generate --budget-usd 5.00
   ```

   Expected result: If neither is set, the config loader defaults budget_usd to 50.0 and that becomes DIATAXIS_BUDGET_USD for the run.

2. Run generate as usual. The harness checks the remaining budget before it starts each page, and again immediately before it builds the call to claude, so a page is never half-paid-for.

   ```console
   diataxis generate --mode howto
   ```

   Expected result: Pages generate normally while budget remains; nothing changes about a working run.

3. When the budget is exhausted, expect the run to refuse to start the next page rather than let a call run out of money mid-generation. Read the exit code.

   ```console
   diataxis generate --budget-usd 5.00 --mode howto; echo "exit: $?"
   ```

   Expected result: budget_require (lib/manifest.sh:143-152) computes what remains: the configured budget minus what this run has spent so far (budget_remaining, lib/manifest.sh:136-141). It's called once per queued page in cmd_generate (bin/diataxis:838) and again inside claude_run before the argv is built (lib/claude.sh:96). If nothing remains, it dies with exit code 20 (EX_BUDGET, lib/preamble.sh:18) rather than starting a page it can't finish:
budget of $5 exhausted (spent $5.02 this run); refusing to start: how-to/control-spend-with-a-budget. Raise --budget-usd or budget_usd in config

4. Know the second belt: even a single call that runs long is capped. The harness passes the run's remaining balance to the claude CLI's own --max-budget-usd flag, so one runaway call can't blow past the ceiling before the harness notices on the next check.

   Expected result: lib/claude.sh:76-79 passes --max-budget-usd with the remaining balance. If a single call would exceed it, claude itself stops, and the harness recognizes "budget"/"Budget" in the error text and maps it to the same exit code 20 (lib/claude.sh:112-113).

5. Resume after raising the budget or waiting for more runway. Pages already generated and recorded in the manifest are not redone.

   ```console
   diataxis generate --budget-usd 15.00
   ```

   Expected result: Pages that finished before the ceiling hit are up to date in .diataxis/manifest.json and are skipped; only the remaining queue calls claude. DIATAXIS_RUN_SPENT (lib/manifest.sh:133) resets to 0 at the start of this new invocation, so the fresh --budget-usd applies to what's left, not to the prior run's spend.

6. Read the spend breakdown at any time, independent of whether a run is capped or not.

   ```console
   diataxis cost --json
   ```

   Expected result: cmd_cost (bin/diataxis:1124-1144) reads the manifest and prints total_usd, page counts, and a by_mode and by_model breakdown of cost_usd. This is lifetime spend recorded across every page ever generated (manifest_total_cost, lib/manifest.sh:160-162), not just the current run's remaining budget.

## Verify it worked

Run `diataxis cost` and confirm total_usd matches what you expect for the pages generated so far. To confirm the refusal behavior itself, set --budget-usd below the cost of the next page and rerun generate: it should exit 20 with a message naming the page it refused to start, and diataxis cost should show no partial page recorded for it.

## Related

- [explanation/model-routing-and-cost](../explanation/model-routing-and-cost.md)
- [how-to/route-modes-to-different-models](../how-to/route-modes-to-different-models.md)
- [how-to/run-a-large-generation-concurrently](../how-to/run-a-large-generation-concurrently.md)
- [reference/lib](../reference/lib.md)
- [reference/bin](../reference/bin.md)

