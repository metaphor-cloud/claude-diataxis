---
title: "Resolve audit findings"
slug: how-to/resolve-audit-findings
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:17:37Z
frozen: false
---

# Resolve audit findings

Work through the output of `diataxis audit` and apply the fix each finding names, for every rule the harness reports: mode_mixing, title_not_task_shaped, unverified_code, broken_citation, stale, orphan, and missing_reference.

## Before you start

- tutorials/generate-your-first-documentation-set
- how-to/regenerate-a-single-page
- explanation/audit-versus-check

## Steps

1. Run the audit and capture its findings as JSON so you can work through them one at a time.

   ```console
   diataxis audit --json > audit-findings.json
   ```

   Expected result: A JSON object with a `findings` array is written to audit-findings.json. Each entry has `path`, `severity`, `rule`, `excerpt`, and `suggestion` fields.

2. If you'd rather read findings on screen first, run the audit without --json; each line already shows the rule and the fix.

   ```console
   diataxis audit
   ```

   Expected result: One line per finding in the form `severity: path [rule]`, followed by `excerpt:` and `suggestion:` lines where present.

3. For any finding with rule `stale`, regenerate the page: its source inputs changed since the page was written, the page was never generated, or a fallback model answered instead of the one requested.

   ```console
   diataxis generate --page how-to/example-page
   ```

   Expected result: The page's meta.json status is `ok` and its manifest entry's content_hash and inputs_hash are updated; the `stale` finding no longer appears on the next audit.

4. For a finding with rule `broken_citation`, regenerate the page so the model re-derives its citations against current source.

   ```console
   diataxis generate --page reference/example-module --force
   ```

   Expected result: The regenerated page's citations all resolve; verify_citations finds no unresolved path or symbol for that page.

5. For a finding with rule `orphan` (a page under docs/ that's in no plan and isn't frozen), choose one of the three actions the suggestion names: add the page to the plan, mark it frozen, or let the harness remove it.

   ```console
   diataxis clean --dry-run
   ```

   Expected result: clean --dry-run lists the page as one it would remove if you don't add it to the plan or freeze it; re-run without --dry-run once you've decided, or add `frozen: true` to the page's frontmatter to keep it untouched.

6. For a finding with rule `missing_reference` (a public symbol with no reference entry), refresh the plan and generate so the symbol gets a reference page.

   ```console
   diataxis plan && diataxis generate --mode reference
   ```

   Expected result: The symbol named in the finding's excerpt now appears in a reference page's `symbols` list in the manifest, and the missing_reference finding clears.

7. For a finding with rule `unverified_code` (a tutorial whose executable steps failed sandbox verification), read the failure detail and fix the tutorial's steps directly, then regenerate so the harness re-executes them.

   ```console
   diataxis generate --page tutorials/example-tutorial --force
   ```

   Expected result: The manifest entry's `verified` field becomes true; `diataxis check` no longer counts this tutorial among unverified tutorials.

8. For a finding with rule `mode_mixing` (a page blends content that belongs to a different Diataxis mode, for example explanation prose inside a how-to), edit the page to remove the out-of-mode content, or split it into a separate page in the correct mode, then regenerate.

   Expected result: The next audit's model pass no longer flags the page for mode_mixing.

9. For a finding with rule `title_not_task_shaped` (a how-to title isn't phrased as a task starting with a verb), rewrite the title in the plan entry and regenerate the page.

   ```console
   jq '(.pages[] | select(.slug == "how-to/example-page") | .title) = "Configure the example"' .diataxis/plan.json > .diataxis/plan.json.tmp && mv .diataxis/plan.json.tmp .diataxis/plan.json
   ```

   Expected result: diataxis generate --page how-to/example-page --force writes a page whose frontmatter title starts with a verb, and the finding clears.

10. Re-run the audit to confirm every finding you addressed is gone.

   ```console
   diataxis audit
   ```

   Expected result: diataxis audit reports fewer findings, or "audit: no findings" if you resolved all of them.

## Verify it worked

Run `diataxis audit --json` again and confirm the `findings` array no longer contains entries for the rules you addressed. For a CI gate, `diataxis check` exits 0 once no finding's severity is in the configured `audit.fail_on` list, no page is stale, and (if `verify.required` is true) no tutorial is unverified.

## Related

- [how-to/regenerate-a-single-page](../how-to/regenerate-a-single-page.md)
- [how-to/gate-pull-requests-on-documentation-freshness](../how-to/gate-pull-requests-on-documentation-freshness.md)
- [how-to/protect-hand-written-pages-from-regeneration](../how-to/protect-hand-written-pages-from-regeneration.md)
- [how-to/remove-generated-pages-that-left-the-plan](../how-to/remove-generated-pages-that-left-the-plan.md)
- [explanation/audit-versus-check](../explanation/audit-versus-check.md)
- [explanation/the-diataxis-mode-contract](../explanation/the-diataxis-mode-contract.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)

