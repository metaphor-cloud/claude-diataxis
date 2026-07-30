---
title: "Regenerate a single page"
slug: how-to/regenerate-a-single-page
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:06:59Z
frozen: false
---

# Regenerate a single page

Run `diataxis generate` against one page or one mode, and override the up-to-date and edited-file skips so that page is rewritten.

## Before you start

- tutorials/generate-your-first-documentation-set
- explanation/staleness-idempotency-and-the-manifest
- how-to/protect-hand-written-pages-from-regeneration

## Steps

1. Find the slug of the page you want to regenerate. Slugs are the plan entries in `.diataxis/plan.json`, and they match the page's path under the docs directory minus the `.md` extension.

   ```console
   jq -r '.pages[].slug' .diataxis/plan.json
   ```

   Expected result: A list of slugs such as `how-to/regenerate-a-single-page` or `reference/lib/adapters`.

2. Narrow the run to that one page with `--page`. You can pass the slug, the full docs path, or a `./`-prefixed path; `diataxis` normalizes all three before matching.

   ```console
   diataxis generate --page how-to/regenerate-a-single-page
   ```

   Expected result: The run queues only the matching page. If nothing matches, diataxis reports 0 pages queued and exits 0 without contacting the model.

3. Equivalently, pass the page's file path under the docs directory instead of its slug.

   ```console
   diataxis generate --page docs/how-to/regenerate-a-single-page.md
   ```

   Expected result: The same single page is queued as in the previous step.

4. If the page is unchanged since its last generation, diataxis skips it by default. Add `--force` to regenerate it anyway.

   ```console
   diataxis generate --page how-to/regenerate-a-single-page --force
   ```

   Expected result: The page is queued and regenerated even though its recorded inputs hash still matches.

5. Note that --force also overrides the skip that protects a page you edited by hand after generation, replacing your edits. Pass it only when you intend that.

   ```

   ```

   Expected result: No files change until you rerun the command; this step is a warning, not an action.

6. Note that --force does not override a page marked frozen, either in the manifest or in its frontmatter. A frozen page is skipped with a warning regardless of --force.

   ```

   ```

   Expected result: A frozen page stays untouched even when --force is passed.

7. To regenerate every page of one mode instead of a single page, use --mode on its own, or combine it with --page to scope both mode and slug at once.

   ```console
   diataxis generate --mode howto --force
   ```

   Expected result: Every how-to page in the plan is regenerated; other modes are left untouched.

## Verify it worked

Run `diataxis check` or inspect `.diataxis/manifest.json` for the page's slug: its generated_at timestamp should be current and its inputs_hash should match a fresh diataxis plan run's inputs.


