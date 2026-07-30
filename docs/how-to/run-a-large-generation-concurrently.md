---
title: "Run a large generation concurrently"
slug: how-to/run-a-large-generation-concurrently
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:22:16Z
frozen: false
---

# Run a large generation concurrently

Raise batch parallelism up to the cap of 4 so a first full documentation generation across many planned pages finishes faster, while trusting that only the parent process ever touches the repository.

## Before you start

- tutorials/generate-your-first-documentation-set
- how-to/review-and-edit-the-page-plan
- how-to/control-spend-with-a-budget

## Steps

1. Confirm the plan is reviewed and up to date before generating at scale, since --concurrency only changes how fast the existing plan is worked through, not what gets planned.

   ```console
   diataxis/bin/diataxis plan
   ```

   Expected result: .diataxis/plan.json is unchanged or updated; git diff shows a reviewable page list.

2. Run generate with --concurrency set to 4, the maximum the harness allows.

   ```console
   diataxis/bin/diataxis generate --concurrency 4
   ```

   Expected result: Log lines show pages being dispatched in batches of up to 4 at a time, for example "[1/40] ..." through "[4/40] ..." appearing together before the next batch starts.

3. If you pass a value above 4 or below 1, expect the harness to clamp it rather than error, so requesting more parallelism than the cap is harmless.

   Expected result: A run with --concurrency 8 behaves identically to --concurrency 4; a run with --concurrency 0 behaves like --concurrency 1.

4. Let each batch run to completion before the next one starts. Each worker in a batch only writes its result to a private temporary directory; nothing lands in the repository until the whole batch's workers finish.

   Expected result: No partial or half-written pages appear under docs/ while a batch is still running.

5. Watch for the parent applying results serially after each batch: this is where docs/*.md files are written and .diataxis/manifest.json is updated, one page at a time, so manifest entries never interleave or race even at concurrency 4.

   Expected result: After each batch, git status shows a batch's worth of new or changed files under docs/, and .diataxis/manifest.json gains matching entries.

6. If a batch trips the model's usage limit mid-run, let the harness stop rather than retrying manually. It records every page completed so far in the manifest and exits with a message telling you to re-run generate later.

   Expected result: The run exits non-zero with a message naming how many pages completed and instructing you to re-run diataxis generate once the limit resets; re-running resumes from the pages still stale, since finished pages are no longer stale.

## Verify it worked

Run `diataxis cost` (or `diataxis generate --concurrency 4 --json` again) and confirm the reported page count matches the plan and no docs/*.md file is missing a manifest entry; re-running the same generate command reports "nothing to do" because every page's inputs_hash now matches.


