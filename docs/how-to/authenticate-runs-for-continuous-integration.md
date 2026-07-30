---
title: "Authenticate runs for continuous integration"
slug: how-to/authenticate-runs-for-continuous-integration
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:36:10Z
frozen: false
---

# Authenticate runs for continuous integration

Supply credentials that `diataxis check` recognizes as bare-capable, so CI runs pass without exiting 16.

## Before you start

- how-to/vendor-the-harness-into-a-repository
- how-to/diagnose-environment-and-authentication-failures

## Steps

1. Understand why this matters: `diataxis check` calls `require_bare_capable`, which dies with exit code 16 unless the harness can run `--bare`. Bare mode skips OAuth and keychain reads, so it only works with a credential the harness can read without a login session.

   ```sh
   require_bare_capable() {
     if [ "${DIATAXIS_BARE_CAPABLE:-0}" -ne 1 ]; then
       die "$EX_NOT_BARE_CAPABLE" \
         "diataxis check requires bare-capable auth so CI runs are reproducible. Export ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN (claude setup-token), or supply an apiKeyHelper via settings_file"
     fi
   }
   ```

   Expected result: You understand that one of three credential shapes is required: an env var token, an env var API key, or a settings file carrying an apiKeyHelper.

2. Pick one of the three bare-capable methods below. `resolve_bare` treats the first two as bare-capable directly from the auth method it detects; the third is trusted on the operator's word that the settings file supplies working credentials.

   ```sh
   resolve_bare() {
     ...
     case "$DIATAXIS_AUTH_METHOD" in
       api_key_env|oauth_token_env) DIATAXIS_BARE_CAPABLE=1 ;;
       *)
         if [ -n "$_settings_file" ]; then
           # A settings file may carry an apiKeyHelper; trust the operator.
           DIATAXIS_BARE_CAPABLE=1
         fi
         ;;
     esac
   ```

   Expected result: You've decided which method fits your CI provider's secret storage.

3. Method A, a long-lived OAuth token: on a machine where you're already logged in, generate a token, then store it as a CI secret.

   ```sh
   claude setup-token
   # copy the printed token into your CI provider's secret store, e.g.:
   gh secret set CLAUDE_CODE_OAUTH_TOKEN --body "<token>"
   ```

   Expected result: The CI secret exists. In the workflow, export it before invoking the harness: `export CLAUDE_CODE_OAUTH_TOKEN="${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}"`.

4. Method B, an API key: set `ANTHROPIC_API_KEY` as a CI secret and export it in the job before running `diataxis`.

   ```sh
   export ANTHROPIC_API_KEY="$YOUR_STORED_SECRET"
   ```

   Expected result: `check_auth` in lib/preamble.sh sets `DIATAXIS_AUTH_METHOD=api_key_env` as soon as this variable is non-empty, before it even tries `claude auth status`.

5. Method C, an apiKeyHelper settings file: write a Claude Code settings JSON file whose `apiKeyHelper` resolves a key at runtime (for example, reading from your CI's secret manager), then point the harness config at it with `settings_file`.

   ```json
   {
     "settings_file": "ci/claude-settings.json"
   }
   ```

   Expected result: `cfg_settings_file` returns the path, and `claude_run` passes `--settings "$DIATAXIS_WORKSPACE/$_cr_settings"` on every generation and check call.

6. Confirm none of the three env vars or the settings file leak into a committed file; set them only in the CI secret store, never in `diataxis.config.json` itself (the `settings_file` key is a path, not the credential).

   Expected result: `git status` shows no credential material added to the repository.

7. Run doctor locally with the same environment variables CI will use, to confirm the auth method resolves before it ever costs a generation call.

   ```sh
   CLAUDE_CODE_OAUTH_TOKEN="$YOUR_TOKEN" diataxis/bin/diataxis doctor
   ```

   Expected result: Output includes a line like `ok  authenticated (method: oauth_token_env)` or `ok  authenticated (method: api_key_env)`, and doctor exits 0.

8. Run `check` itself in the same shell to confirm bare-capability, not just authentication.

   ```sh
   CLAUDE_CODE_OAUTH_TOKEN="$YOUR_TOKEN" diataxis/bin/diataxis check
   ```

   Expected result: The command exits 0, 30, 31, or 32 (a documentation-content verdict), never 16. If it still exits 16, the credential did not resolve; see the diagnosis how-to.

## Verify it worked

Run `diataxis check` in the CI job with only the environment variables (or settings file) that CI itself will have, no interactive login. Exit code 16 means auth is present but not bare-capable; any other code means the harness moved past the bare-capability gate and evaluated documentation freshness instead.

## Related

- [how-to/diagnose-environment-and-authentication-failures](../how-to/diagnose-environment-and-authentication-failures.md)
- [how-to/gate-pull-requests-on-documentation-freshness](../how-to/gate-pull-requests-on-documentation-freshness.md)
- [explanation/reproducibility-and-bare-mode](../explanation/reproducibility-and-bare-mode.md)

