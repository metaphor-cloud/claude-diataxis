---
title: "Diagnose environment and authentication failures"
slug: how-to/diagnose-environment-and-authentication-failures
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:07:05Z
frozen: false
---

# Diagnose environment and authentication failures

Turn a `diataxis doctor` failure into the specific fix it needs, using its distinct exit code to go straight to the remediation instead of guessing.

## Before you start

- how-to/vendor-the-harness-into-a-repository
- tutorials/generate-your-first-documentation-set

## Steps

1. Run doctor from the repository root. It runs the same preamble every subcommand runs, but prints a line per check instead of staying quiet.

   ```console
   $ diataxis/bin/diataxis doctor
   ```

   Expected result: Either every check prints `ok` and the command exits 0 with "doctor: all checks passed" on stderr, or one check prints `fail` with a remediation line and the process exits with that check's code.

2. Read the exit code (`echo $?` after the run, or the CI job's reported status) and match it against the table below. Codes 10 through 16 are the ones doctor's checks can produce; each belongs to exactly one check in `preamble_run`.

   Expected result: You know which single check failed before reading the fail line.

3. Exit 10 (`EX_CLAUDE_MISSING`): the `claude` CLI is not on `PATH`. Install it, then confirm it resolves.

   ```console
   $ npm i -g @anthropic-ai/claude-code
   $ command -v claude
   ```

   Expected result: `command -v claude` prints a path.

4. Exit 11 (`EX_CLAUDE_OLD`): the installed `claude` is older than the harness's minimum (`2.1.205`), or its version string could not be parsed. `--json-schema` validation and `/model` as an argument only landed at that version; older CLIs silently ignore an invalid schema instead of failing loudly. Update and recheck the version.

   ```console
   $ claude update
   $ claude --version
   ```

   Expected result: The printed version is 2.1.205 or newer.

5. Exit 12 (`EX_UNAUTH`): the CLI is not authenticated. For interactive use, log in. For CI or any run that must be reproducible, generate a long-lived token instead and export it (or export an API key) rather than relying on keychain login.

   ```console
   $ claude auth login
   # or, for CI:
   $ claude setup-token
   $ export CLAUDE_CODE_OAUTH_TOKEN=...   # or export ANTHROPIC_API_KEY=...
   ```

   Expected result: Doctor's auth check passes and reports the auth method it detected (`oauth_token_env`, `api_key_env`, or a subscription method).

6. Exit 13 (`EX_JQ_MISSING`): `jq` is missing or older than 1.6, the harness's only parser. Install a current `jq` and recheck its version.

   ```console
   $ brew install jq   # or: apt-get install jq
   $ jq --version
   ```

   Expected result: `jq --version` reports 1.6 or newer.

7. Exit 14 (`EX_GIT_MISSING`): `git` is missing, or the current directory is not inside a git work tree. Install git and run `diataxis` from within the repository you want documented.

   Expected result: `git rev-parse --is-inside-work-tree` prints `true` from the directory you run `diataxis` in.

8. Exit 15 (`EX_UNWRITABLE`): the docs directory or `.diataxis/` exists but isn't writable, or their parent isn't writable so they can't be created. Fix permissions on the reported path.

   ```console
   $ chmod u+w docs .diataxis 2>/dev/null; true
   ```

   Expected result: The path named in the fail line is writable by the current user.

9. Exit 16 (`EX_NOT_BARE_CAPABLE`): `diataxis.config.json` sets `"bare": true`, but the detected auth method can't run in `--bare` mode (bare mode skips OAuth and keychain reads). Either export `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` so auth comes from the environment, supply an `apiKeyHelper` via a settings file, or set `"bare"` to `"auto"` or `false` in the config.

   Expected result: Doctor's writability check runs (bare resolution happens just before it) without dying with this code.

10. Re-run doctor after applying the fix for the reported code.

   ```console
   $ diataxis/bin/diataxis doctor
   ```

   Expected result: The process exits 0 and stderr ends with "doctor: all checks passed".

## Verify it worked

`diataxis doctor` exits 0. With `--json`, the printed object has `"status":"ok"` and reports `claude_version`, `auth_method`, and `bare_capable`.

## Related

- [how-to/authenticate-runs-for-continuous-integration](../how-to/authenticate-runs-for-continuous-integration.md)
- [explanation/reproducibility-and-bare-mode](../explanation/reproducibility-and-bare-mode.md)
- [reference/lib](../reference/lib.md)

