---
title: "Inspect a run without calling the model"
slug: how-to/inspect-a-run-without-calling-the-model
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:42:33Z
frozen: false
---

# Inspect a run without calling the model

Confirm which model, effort, tool restrictions and budget flags a diataxis run would use, without spending any budget or making an API call.

## Before you start

- tutorials/generate-your-first-documentation-set
- how-to/route-modes-to-different-models
- how-to/control-spend-with-a-budget

## Steps

1. Add the global --dry-run flag to the subcommand you want to inspect (plan, generate, or audit). Scope generate/audit to one page with --page if you only care about a single call.

   ```console
   diataxis generate --mode howto --page how-to/example --dry-run
   ```

   Expected result: The command exits 0 without contacting the API.

2. Do not combine --dry-run with --json; the harness rejects that combination outright.

   Expected result: Using both flags together fails with "--dry-run and --json are mutually exclusive" before any work starts.

3. Read the printed argv: the first line is the literal string "claude", each following line is exactly one argument to that command, and a blank line marks the end of the block.

   Expected result: One argv token per line, e.g. -p, --model, claude-..., --allowedTools, Read,Grep,Glob, --permission-mode, dontAsk, --strict-mcp-config, --output-format, json, --json-schema, {...}, --max-turns, 24, and finally the task prompt as the last line before the blank terminator.

4. Check --model and, if present, --effort to confirm which model and reasoning effort this mode is routed to.

   Expected result: The value after --model matches what you expect for that mode's configuration; --effort is present only when the mode has an effort configured.

5. Check --allowedTools and --permission-mode to confirm the call is read-only, and --strict-mcp-config to confirm no ambient MCP servers can attach.

   Expected result: --allowedTools reads exactly "Read,Grep,Glob", --permission-mode reads "dontAsk", and --strict-mcp-config has no accompanying --mcp-config.

6. Check for --max-budget-usd, --fallback-model, --settings, and a leading --bare to confirm the budget cap, opus fallback wiring, settings file, and bare-mode isolation are what you expect.

   Expected result: --max-budget-usd shows the remaining run budget when one is configured; --fallback-model appears only when --model is an opus model; --bare appears as the first argument only when bare mode resolved to on.

## Verify it worked

Because --dry-run returns before budget_require and before the claude binary is ever invoked, no cost is recorded: run `diataxis cost` before and after and confirm the total is unchanged, and for `generate` confirm each queued page's meta.json (or its logged status) reads "dry_run" rather than "ok" or "failed".

## Related

- [how-to/route-modes-to-different-models](../how-to/route-modes-to-different-models.md)
- [how-to/control-spend-with-a-budget](../how-to/control-spend-with-a-budget.md)
- [how-to/regenerate-a-single-page](../how-to/regenerate-a-single-page.md)
- [explanation/reproducibility-and-bare-mode](../explanation/reproducibility-and-bare-mode.md)
- [explanation/model-routing-and-cost](../explanation/model-routing-and-cost.md)

