---
title: "Run the harness test suite"
slug: how-to/run-the-harness-test-suite
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:18:02Z
frozen: false
---

# Run the harness test suite

Run shellcheck and the bats suite exactly as continuous integration does, using the hermetic PATH shim, and optionally exercise the one live smoke test under a capped budget.

## Before you start

- how-to/vendor-the-harness-into-a-repository
- explanation/why-the-harness-owns-the-filesystem

## Steps

1. Install shellcheck and bats (with jq) if they are not already on your PATH. On Debian/Ubuntu, this is what CI runs.

   ```sh
   sudo apt-get update -q && sudo apt-get install -y shellcheck bats jq
   ```

   Expected result: shellcheck --version and bats --version both print a version.

2. From the repository root, run shellcheck over exactly the files continuous integration lints, with the POSIX sh dialect.

   ```sh
   shellcheck -s sh bin/diataxis lib/*.sh lib/adapters/*.sh tests/helpers/claude install.sh
   ```

   Expected result: No output and exit status 0. Any warning is a real finding, not a false positive; `.shellcheckrc` only disables SC1090 (adapters are sourced through a variable path by design), and any other suppression is an inline directive at the specific line.

3. Run the bats suite.

   ```sh
   bats tests/
   ```

   Expected result: Every test reports 'ok'. The suite stubs claude as a PATH shim, so no network calls or credentials are needed.

4. If a test fails, read the sandbox mechanism before debugging: each test builds a hermetic PATH directory of symlinks to real coreutils plus a claude stub, so the test only sees the tools it's meant to. tests/helpers/test_helper.bash defines make_sandbox (build the PATH shim, optionally omitting named tools to test missing-dependency paths), make_repo (a throwaway git repo, optionally seeded from a tests/fixtures/*/repo fixture), and dtx (run bin/diataxis inside that sandbox with controlled credential env vars).

   Expected result: You can trace which tools a failing test had available, and reproduce its sandbox by hand if needed.

5. Optionally, run the one live smoke test, which makes a real, low-cost call to claude instead of the stub. Set DIATAXIS_LIVE=1 and the suite caps that test's spend at --budget-usd 0.50; leave the variable unset to skip it, which is the default in continuous integration.

   ```sh
   DIATAXIS_LIVE=1 bats tests/
   ```

   Expected result: The live test reports 'ok' (or is skipped when DIATAXIS_LIVE is unset), and no other test's behavior changes.

## Verify it worked

Both commands exit 0: `shellcheck -s sh bin/diataxis lib/*.sh lib/adapters/*.sh tests/helpers/claude install.sh` with no output, and `bats tests/` with every test marked 'ok'. This is the same pair of steps the shellcheck and bats jobs in .github/workflows/ci.yml run on every push and pull request.

## Related

- [explanation/why-posix-shell-and-jq](../explanation/why-posix-shell-and-jq.md)
- [how-to/verify-tutorial-code-in-a-container](../how-to/verify-tutorial-code-in-a-container.md)
- [how-to/gate-pull-requests-on-documentation-freshness](../how-to/gate-pull-requests-on-documentation-freshness.md)

