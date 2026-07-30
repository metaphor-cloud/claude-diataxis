---
title: "Gate pull requests on documentation freshness"
slug: how-to/gate-pull-requests-on-documentation-freshness
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:06:56Z
frozen: false
---

# Gate pull requests on documentation freshness

Add a pull-request-only CI job that runs `diataxis check` and fails the job when generated pages are stale, fail audit, or have unverified tutorials, using the shipped workflow snippet and its exit code contract.

## Before you start

- how-to/vendor-the-harness-into-a-repository
- how-to/authenticate-runs-for-continuous-integration
- tutorials/generate-your-first-documentation-set

## Steps

1. Copy the shipped workflow snippet into your repository's workflow directory.

   ```
   mkdir -p .github/workflows
   cp diataxis/share/integrations/github-actions-docs-check.yml .github/workflows/docs-check.yml
   ```

   Expected result: A new file .github/workflows/docs-check.yml exists, triggered on `pull_request:` with a single `docs-check` job.

2. Confirm the job only runs `check`, not `generate`. The snippet's `diataxis check` step writes nothing to the repository; keep it that way.

   Expected result: The workflow contains exactly one diataxis invocation, `diataxis/bin/diataxis --json check`, and no `generate` step.

3. Add a long-lived OAuth token as a repository secret named CLAUDE_CODE_OAUTH_TOKEN, generated with `claude setup-token`. The job reads it into the `CLAUDE_CODE_OAUTH_TOKEN` environment variable of the `diataxis check` step.

   Expected result: The secret CLAUDE_CODE_OAUTH_TOKEN is set in the repository or organization settings; the workflow YAML references it as `${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}`.

4. Note why `check` needs this specific auth: it calls `require_bare_capable`, which fails immediately with exit code 16 unless the auth method is env-credential based (API key or OAuth token env var). This is what keeps a CI run reproducible: no local CLAUDE.md, hooks, or keychain state can leak into the result.

   Expected result: Understood as background only; no action if the token secret from the previous step is already in place.

5. Open a pull request that touches a documented source file, or intentionally edit a generated page under docs/ by hand, and watch the docs-check job run.

   Expected result: The job runs `diataxis check`, which computes local rules (stale, broken_citation, orphan, missing_reference, unverified tutorials, model divergence) with no model calls, and posts PR annotations for each finding via the `jq` step that maps `severity` to `::error` or `::warning`.

6. Read the job's exit code against the mapping in lib/preamble.sh and README.md: 30 means an audit finding at a severity in `audit.fail_on` (default just `error`), 31 means at least one page is stale, 32 means an unverified tutorial. `cmd_check` in bin/diataxis checks audit failures first, then staleness, then unverified tutorials, so a run failing on more than one condition still reports whichever check hits first.

   Expected result: A red job with exit code 31 tells you to regenerate stale pages; 32 tells you a tutorial failed its sandboxed verification pass and needs a repair or a manual fix; 30 tells you an audit rule (mode_mixing, title_not_task_shaped, broken_citation, etc.) needs attention.

7. Regenerate the affected pages locally or from a separate scheduled/manual workflow, then commit the updated docs/ and .diataxis/manifest.json.

   ```
   diataxis/bin/diataxis generate
   ```

   Expected result: The manifest's inputs_hash for the affected pages now matches current sources, and the working tree has updated Markdown files to commit.

8. Push the commit and re-run the pull request; the docs-check job should now exit 0.

   Expected result: The docs-check job passes with no findings, or only findings at severities outside `audit.fail_on`.

## Verify it worked

The docs-check job on the pull request exits 0 and shows no error-level PR annotations. Deliberately staling a page (editing a source file listed in a page's `sources` without regenerating) reproduces exit code 31 and an `stale` annotation, confirming the gate is live.


