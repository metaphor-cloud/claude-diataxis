---
title: "Vendor the harness into a repository"
slug: how-to/vendor-the-harness-into-a-repository
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:07:43Z
frozen: false
---

# Vendor the harness into a repository

Commit the diataxis harness (bin, lib, prompts, schemas, share) into a target repository so its `diataxis` CLI and a starter config are available for that repo's own documentation workflow.

## Before you start

- You have a local checkout of the claude-diataxis repository, or know its git URL, and have `git` on PATH.
- You have write access to the target repository's working tree.

## Steps

1. Run install.sh against the target repository, from a checkout of the harness.

   ```sh
   path/to/claude-diataxis/install.sh path/to/your-repo
   ```

   Expected result: Output ends with `vendored diataxis into path/to/your-repo/diataxis` followed by three next-step lines.

2. If you do not have a local checkout, install by piping the script through curl instead, setting DIATAXIS_REPO_URL to this repository's git URL.

   ```sh
   curl -fsSL <raw-url>/install.sh | DIATAXIS_REPO_URL=<this repo's git url> sh
   ```

   Expected result: The script clones the harness to a temporary directory, copies it into `./diataxis`, and removes the temporary clone on exit.

3. Confirm the starter config was written, or was left alone if one already existed.

   Expected result: install.sh prints `wrote path/to/your-repo/diataxis.config.json (starter config)` on a first install, or `kept existing path/to/your-repo/diataxis.config.json` if a config was already present.

4. If `diataxis/` already exists at the target, install.sh refuses to overwrite it. Update the vendored copy with git subtree or git submodule instead of re-running install.sh.

   ```sh
   git subtree add --prefix diataxis <url> main --squash
   ```

   Expected result: install.sh exits with `error: <target>/diataxis already exists; remove it or update via git subtree/submodule instead` if you try to install over an existing vendor directory.

5. Commit the vendored directory (and the config, if this is a first install).

   ```sh
   git add diataxis diataxis.config.json && git commit -m "Vendor the diataxis harness"
   ```

   Expected result: A commit containing `diataxis/bin`, `diataxis/lib`, `diataxis/prompts`, `diataxis/schemas`, `diataxis/share` and `diataxis/install.sh`.

6. Run doctor from the vendored copy to confirm the environment and auth are usable.

   ```sh
   diataxis/bin/diataxis doctor
   ```

   Expected result: Exits 0 with `doctor: all checks passed` on stderr. A non-zero exit means an environment or auth problem; see the diagnose-environment-and-authentication-failures how-to.

## Verify it worked

`diataxis/bin/diataxis doctor` exits 0, and `git log -1 --stat` on the target repository shows the vendored `diataxis/` tree (bin, lib, prompts, schemas, share) plus `diataxis.config.json` as committed files.

## Related

- [how-to/diagnose-environment-and-authentication-failures](../how-to/diagnose-environment-and-authentication-failures.md)
- [tutorials/generate-your-first-documentation-set](../tutorials/generate-your-first-documentation-set.md)
- [explanation/why-the-harness-owns-the-filesystem](../explanation/why-the-harness-owns-the-filesystem.md)
- [explanation/why-posix-shell-and-jq](../explanation/why-posix-shell-and-jq.md)

