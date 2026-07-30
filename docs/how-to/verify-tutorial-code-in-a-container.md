---
title: "Verify tutorial code in a container"
slug: how-to/verify-tutorial-code-in-a-container
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:40:35Z
frozen: false
---

# Verify tutorial code in a container

Run a tutorial's executable code blocks inside a container instead of an ephemeral host directory, and tune how many languages get executed and how many repair attempts are allowed.

## Before you start

- tutorials/generate-your-first-documentation-set
- how-to/control-spend-with-a-budget

## Steps

1. Open diataxis.config.json at the repository root and find the verify block. If it is absent, the harness applies these defaults.

   ```json
   "verify": {
     "mode": "sandbox",
     "required": true,
     "max_repairs": 2,
     "executable_languages": ["bash", "sh", "console"]
   }
   ```

   Expected result: You can see the current mode, max_repairs and executable_languages, or confirm the block is missing and defaults apply.

2. Add sandbox_command, a string the harness runs with the step script's path appended as its final argument. Point it at a container that mounts the harness's temporary directory so the script inside the container resolves to the same path the harness passes.

   ```json
   "verify": {
     "mode": "sandbox",
     "required": true,
     "max_repairs": 2,
     "sandbox_command": "docker run --rm -v /tmp:/tmp -w /tmp my-verify-image sh",
     "executable_languages": ["bash", "sh", "console"]
   }
   ```

   Expected result: diataxis.config.json still validates: sandbox_command is typed string or null in schemas/config.json, so a bad value fails config_load with exit code 2, JSON pointer /verify/sandbox_command.

3. Match the mount to where the harness actually creates its working directories. The harness's per-run temp directory is created under $TMPDIR (or /tmp if unset); each step script for a tutorial under verification lives inside that tree. Mount the same root your shell's TMPDIR resolves to, not a hardcoded /tmp, if your environment sets TMPDIR elsewhere (for example under macOS's per-user /var/folders path).

   Expected result: echo "${TMPDIR:-/tmp}" tells you the path to mount; the container's sh must be able to read and execute a file at that same absolute path.

4. If your tutorials contain fenced blocks in languages beyond bash, sh and console, for example python, add those languages to executable_languages so tutorial_verify actually runs them instead of skipping them silently. Only add a language your sandbox image has an interpreter for.

   ```json
   "executable_languages": ["bash", "sh", "console", "python"]
   ```

   Expected result: A python-tagged fenced block in a tutorial is now extracted to a step script and executed through sandbox_command.

5. Tune max_repairs, the cap on repair attempts when a step script exits non-zero. Lower it if failures should surface to a human sooner; raise it if your container needs more attempts for the model to adapt to constraints (like an unavailable package) that a plain host run would not hit.

   ```json
   "max_repairs": 1
   ```

   Expected result: A tutorial that still fails after 1 repair attempt is written with verified: false frontmatter instead of retrying a second time.

6. Regenerate a tutorial page to exercise the new sandbox_command, forcing regeneration since the page is presumably already up to date.

   ```sh
   diataxis/bin/diataxis generate --mode tutorial --force --verbose
   ```

   Expected result: The verbose log shows "verifying tutorial <slug> (executing its code blocks)..."; each step script runs through your sandbox_command rather than a bare `sh -e` on the host.

## Verify it worked

Open the generated tutorial page and check its frontmatter: `verified: true` means every executable block ran successfully inside the container within the configured max_repairs. If verification still fails, the log prints the failing step number, its command block, and the last 40 lines of output, now originating from inside your container image rather than the host shell.


