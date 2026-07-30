---
title: "Protect hand-written pages from regeneration"
slug: how-to/protect-hand-written-pages-from-regeneration
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:17:15Z
frozen: false
---

# Protect hand-written pages from regeneration

Mark a documentation page so `diataxis generate` and `diataxis clean` never touch it again, whether it started as a generated page you then hand-edited or a page you wrote yourself.

## Before you start

- how-to/regenerate-a-single-page
- how-to/review-and-edit-the-page-plan
- explanation/staleness-idempotency-and-the-manifest

## Steps

1. Open the page under its docs directory. Every generated page has a YAML frontmatter block at the top, delimited by `---` lines, ending in a `frozen: false` key.

   ```yaml
   ---
   title: "Example page"
   slug: how-to/example
   mode: howto
   generated_by: diataxis
   generated_at: 2026-07-30T00:00:00Z
   verified: true
   frozen: false
   ---
   ```

   Expected result: You can see the `frozen: false` line that render_frontmatter wrote when the page was generated.

2. Change that line to `frozen: true` and save the file. If you are protecting a page you wrote entirely by hand with no existing frontmatter, add a two-line frontmatter block containing just `frozen: true` between opening and closing `---` markers instead.

   ```yaml
   frozen: true
   ```

   Expected result: The file on disk now has a line reading exactly `frozen: true` inside its frontmatter block.

3. Confirm the harness now treats the page as frozen by running generate against it with verbose logging.

   ```console
   diataxis generate --page how-to/example --verbose
   ```

   Expected result: Output includes `skip how-to/example: frozen`, and the file on disk is unchanged.

4. If the page later leaves the page plan entirely, confirm `diataxis clean` also leaves it alone.

   ```console
   diataxis clean --dry-run
   ```

   Expected result: The page is not listed as something that would be removed; frozen pages are kept even when clean would otherwise delete them.

## Verify it worked

Run `diataxis generate --verbose` (or `--page` for just this slug) and check the log line for the page: it must read `skip <slug>: frozen`, not `skip <slug>: up to date` or a generation attempt. The file's frontmatter still has `frozen: true`, and the file's content is byte-for-byte what you left it, since `page_is_frozen` short-circuits before the harness computes a new content hash or writes anything.

## Related

- [how-to/remove-generated-pages-that-left-the-plan](../how-to/remove-generated-pages-that-left-the-plan.md)
- [how-to/resolve-audit-findings](../how-to/resolve-audit-findings.md)
- [how-to/regenerate-a-single-page](../how-to/regenerate-a-single-page.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [explanation/why-the-harness-owns-the-filesystem](../explanation/why-the-harness-owns-the-filesystem.md)

