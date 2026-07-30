---
title: "Remove generated pages that left the plan"
slug: how-to/remove-generated-pages-that-left-the-plan
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:22:06Z
frozen: false
---

# Remove generated pages that left the plan

Delete manifest-tracked documentation pages that no longer appear in the current plan, without disturbing frozen or hand-edited pages.

## Before you start

- how-to/review-and-edit-the-page-plan
- how-to/protect-hand-written-pages-from-regeneration
- explanation/staleness-idempotency-and-the-manifest

## Steps

1. Refresh the plan first, so `clean` compares against the current set of pages rather than a stale one.

   ```console
   diataxis plan
   ```

   Expected result: The command updates .diataxis/plan.json and prints how many pages it wrote, grouped by mode.

2. Preview what clean would remove before deleting anything.

   ```console
   diataxis --dry-run clean
   ```

   Expected result: One 'would remove SLUG' line per manifest-tracked page that is no longer in .diataxis/plan.json. Pages that are frozen or hand-edited are not listed.

3. Run clean for real once the preview looks right.

   ```console
   diataxis clean
   ```

   Expected result: One 'removed SLUG' line per page actually deleted. Each removed page's markdown file is deleted from the docs directory and its entry is dropped from .diataxis/manifest.json.

4. If a page you expected to be removed instead prints 'keep SLUG: edited by hand since generation', pass --force to remove it anyway. Only do this once you have confirmed the hand edits are not worth preserving.

   ```console
   diataxis --force clean
   ```

   Expected result: Pages previously kept because their on-disk content diverged from the manifest's recorded content_hash are now removed too. Frozen pages are still kept regardless of --force.

## Verify it worked

Run `diataxis --json clean` (after a normal run with nothing left to remove) and confirm it prints {"command":"clean","status":"ok"}; `git status` should show only the deletions you expected, and any page marked `frozen: true` in its frontmatter or manifest entry should still be present on disk.

## Related

- [how-to/review-and-edit-the-page-plan](../how-to/review-and-edit-the-page-plan.md)
- [how-to/protect-hand-written-pages-from-regeneration](../how-to/protect-hand-written-pages-from-regeneration.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [explanation/why-the-harness-owns-the-filesystem](../explanation/why-the-harness-owns-the-filesystem.md)

