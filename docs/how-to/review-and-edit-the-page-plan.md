---
title: "Review and edit the page plan"
slug: how-to/review-and-edit-the-page-plan
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:08:29Z
frozen: false
---

# Review and edit the page plan

Review the diff in .diataxis/plan.json before spending money on generation, edit its entries safely, and respond correctly to the more-than-three-tutorials warning and the slug/mode mismatch failure.

## Before you start

- tutorials/generate-your-first-documentation-set

## Steps

1. Produce or refresh the plan.

   ```console
   diataxis/bin/diataxis plan
   ```

   Expected result: A log line such as "plan: wrote 42 pages to .diataxis/plan.json (tutorial: 2, howto: 14, reference: 20, explanation: 6)". If the plan wants more than three tutorials, a warning appears; see the step below for handling it.

2. Before doing anything else, diff the plan against what is committed. This is the point where review is cheap: nothing has been generated yet.

   ```console
   git diff .diataxis/plan.json
   ```

   Expected result: A JSON diff showing exactly which page entries were added, removed, or changed (slug, mode, title, rationale, sources, priority, audience).

3. For a more readable view of what changed, list the entries in a compact form.

   ```console
   jq '.pages[] | {slug, mode, title, priority}' .diataxis/plan.json
   ```

   Expected result: One object per planned page, in the slug order the plan was written in.

4. Edit .diataxis/plan.json directly in a text editor to change a title, rationale, priority, or audience, or to drop a page entirely. The harness only reads this file for `generate`, `audit`, and `check`; it does not re-validate your hand edits against a schema. Do not hand-edit entries whose slug starts with `reference/` — the harness derives them mechanically from the symbol inventory and merges them back in on every `diataxis plan` run, so edits to them are discarded.

   Expected result: The file still parses as valid JSON, and `jq '.pages | length' .diataxis/plan.json` returns the count you expect.

5. If you change a page's mode, keep its slug prefix aligned: `tutorials/` for mode `tutorial`, `how-to/` for mode `howto`, `explanation/` for mode `explanation`. This is enforced only on the model's own output during `diataxis plan` itself — if you see the run fail with "plan produced slug '...' that does not match its mode directory", that happens before plan.json is written, so there is nothing to edit yet; re-run `diataxis plan`.

   ```console
   diataxis/bin/diataxis plan
   ```

   Expected result: The run either completes and writes plan.json, or fails again with the same message (in which case check the model output, not the plan file, since it hasn't been written).

6. Act on the more-than-three-tutorials warning. Open plan.json, find the entries with `"mode": "tutorial"`, and either delete the ones that do not need to be a guided lesson or change them to `"mode": "howto"` and rename their slug from `tutorials/...` to `how-to/...` to match. The warning does not block generation on its own, but a repository with many tutorials usually means some of them are really how-to guides.

   Expected result: `jq '[.pages[] | select(.mode == "tutorial")] | length' .diataxis/plan.json` returns 3 or fewer, or you have deliberately decided to keep more.

7. Keep slugs stable across refreshes. Each `diataxis plan` run feeds the existing plan.json back to the model as context, but nothing forces slugs to survive verbatim. Renaming or dropping a slug orphans its already-generated page (flagged by the `orphan` rule) and produces a fresh "never generated" entry for the new slug. Treat any unexpected slug in the diff as a signal to investigate, not to accept automatically.

   Expected result: git diff .diataxis/plan.json shows slug changes only where you intended them.

8. Confirm your edits are what `generate` will actually use, without spending anything, by dry-running a specific page.

   ```console
   diataxis/bin/diataxis generate --dry-run --page <slug>
   ```

   Expected result: The printed claude argv reflects your edited title, mode, and sources for that slug.

9. Commit the reviewed plan.

   ```console
   git add .diataxis/plan.json && git commit -m "Review generated page plan"
   ```

   Expected result: A clean `git status` with the plan change committed.

## Verify it worked

`git diff .diataxis/plan.json` matches only the changes you intended, `jq '[.pages[] | select(.mode == "tutorial")] | length'` is 3 or fewer (or a deliberate exception), and `diataxis generate --dry-run --page <slug>` for any edited page shows the title and mode you set.

## Related

- [explanation/the-diataxis-mode-contract](../explanation/the-diataxis-mode-contract.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [how-to/regenerate-a-single-page](../how-to/regenerate-a-single-page.md)
- [how-to/remove-generated-pages-that-left-the-plan](../how-to/remove-generated-pages-that-left-the-plan.md)

