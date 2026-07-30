---
title: "Route modes to different models"
slug: how-to/route-modes-to-different-models
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:40:12Z
frozen: false
---

# Route modes to different models

Override which model and effort level each generation mode uses, set the fallback model for overloaded Opus calls, and control the inventory-size threshold that routes reference pages to the cheaper bulk pass.

## Before you start

- how-to/vendor-the-harness-into-a-repository
- tutorials/generate-your-first-documentation-set

## Steps

1. Open (or create) `diataxis.config.json` at the workspace root and locate or add the `models` block. Unset keys fall back to the shipped defaults, so you only need to list the modes you want to change.

   ```json
   {
     "models": {
       "plan":           {"model": "claude-opus-5",   "effort": "high"},
       "tutorial":       {"model": "claude-opus-5",   "effort": "high"},
       "explanation":    {"model": "claude-opus-5",   "effort": "high"},
       "howto":          {"model": "claude-sonnet-5", "effort": "medium"},
       "reference":      {"model": "claude-sonnet-5", "effort": "medium"},
       "reference_bulk": {"model": "claude-haiku-4-5"},
       "audit":          {"model": "claude-sonnet-5", "effort": "medium"},
       "fallback":       "claude-sonnet-5"
     }
   }
   ```

   Expected result: The file parses as valid JSON. This is the exact default block the harness ships, so pasting it unedited changes nothing.

2. Override a mode's model by editing its `model` field. Use an exact model id, not a family alias, so a new family release cannot silently change your output.

   ```json
   "howto": {"model": "claude-opus-5", "effort": "medium"}
   ```

   Expected result: The next run of that mode passes `--model claude-opus-5` to `claude`, visible in the `-> howto: calling claude-opus-5...` log line.

3. Override a mode's reasoning effort by editing its `effort` field, or omit the field entirely to run without an effort flag (this is the default for `reference_bulk`).

   ```
   "explanation": {"model": "claude-opus-5", "effort": "medium"}
   ```

   Expected result: The call log shows the new effort, for example `calling claude-opus-5 (effort medium)...`.

4. Set the fallback model used when an Opus call is overloaded. Every call whose configured model contains `opus` automatically gets `--fallback-model <models.fallback>` appended; other modes are unaffected.

   ```json
   "fallback": "claude-sonnet-5"
   ```

   Expected result: No visible change during a normal run. If Opus returns overloaded, the CLI retries on the fallback model instead of failing the call.

5. Know what happens if the fallback model actually engages: the harness records the model that answered per page, and `diataxis check` marks that page stale if it differs from the mode's configured model, rather than accepting the substitution silently.

   Expected result: N/A: this is existing behavior to be aware of, not a step to perform.

6. Leave `reference_bulk` configured (or remove it) to control routing for large reference pages. A reference page whose source files together yield 25 or more inventory symbols routes to `reference_bulk` instead of `reference`, on the reasoning that converting an already-extracted symbol list to prose does not need Sonnet-level judgment.

   ```json
   "reference_bulk": {"model": "claude-haiku-4-5"}
   ```

   Expected result: For a page crossing the 25-symbol threshold, the log line reads `-> reference_bulk: calling claude-haiku-4-5...` instead of `-> reference: calling claude-sonnet-5...`.

7. To disable bulk routing entirely and force all reference pages through the standard `reference` model regardless of symbol count, remove the `reference_bulk` key (or set its value to `null`).

   ```json
   "models": {
     "reference_bulk": null
   }
   ```

   Expected result: Reference pages with 25 or more symbols now log `-> reference: calling claude-sonnet-5...` instead of routing to Haiku.

8. Confirm your override loads correctly by running a dry run and inspecting the emitted argv for the mode you changed.

   ```console
   diataxis generate --dry-run
   ```

   Expected result: The printed argv for the affected mode includes `--model <your model>` and, if set, `--effort <your effort>`.

## Verify it worked

Run a real generation for a page in the mode you changed and check the `-> <mode>: calling <model>...` / `<- <mode>: done in ...` log lines: the model and effort shown must match your override. For a reference page near the 25-symbol threshold, confirm the call mode logged is `reference_bulk` or `reference` as you intended.


