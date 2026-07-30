---
title: "Configure a multi-language monorepo"
slug: how-to/configure-a-multi-language-monorepo
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:13:24Z
frozen: false
---

# Configure a multi-language monorepo

Point the harness at every language directory in a monorepo, so each workspace gets the right adapter and its generated pages are namespaced by workspace name.

## Before you start

- The harness is already vendored into the repository (how-to/vendor-the-harness-into-a-repository)
- You have run diataxis init at least once, so diataxis.config.json exists

## Steps

1. Open diataxis.config.json and find the workspaces array. By default it contains a single entry pointing at the repository root with the adapter set to auto-detect.

   ```json
   "workspaces": [{"path": ".", "adapter": "auto", "name": null}]
   ```

   Expected result: You see the default single-workspace entry.

2. Replace it with one entry per language directory. Each entry needs a path relative to the repository root; adapter and name are optional.

   ```json
   "workspaces": [
     {"path": "backend", "adapter": "go", "name": "backend"},
     {"path": "frontend", "adapter": "typescript", "name": "frontend"},
     {"path": "scripts", "adapter": "shell", "name": "scripts"}
   ]
   ```

   Expected result: The config file has one workspace object per directory you want documented separately.

3. For a workspace whose language you don't want to hardcode, set adapter to "auto" instead of naming one. The harness runs adapter_detect for rust, go, python, typescript, then shell, in that order, and picks the first that recognizes the directory; shell is checked last because most repositories contain some shell, so it only claims a workspace no other adapter recognizes.

   ```json
   {"path": "tools", "adapter": "auto", "name": "tools"}
   ```

   Expected result: No error is required here; auto-detection happens at plan/generate time.

4. The adapter field, when set explicitly, must be one of the values the config schema allows: auto, rust, go, python, typescript, or shell. Any other value fails config validation.

   Expected result: diataxis exits with a config invalid error citing the workspaces/<index>/adapter pointer if you typo an adapter name.

5. Set name on each workspace to control how its pages are namespaced. The harness uses name if present, falling back to the workspace's path when name is null.

   ```
   {"path": "services/billing", "adapter": "python", "name": "billing"}
   ```

   Expected result: Reference pages derived from this workspace group symbols under the "billing" workspace label instead of the full path "services/billing".

6. Run diataxis plan to regenerate the page inventory against the new workspace list.

   ```console
   diataxis plan
   ```

   Expected result: The command logs how many pages it wrote, broken down by mode, and does not warn about any workspace.

7. If a workspace's adapter cannot be auto-detected, the harness skips it with a warning rather than failing the whole run. Watch stderr for this and either pin the adapter explicitly or confirm the directory has no source the harness should document.

   ```console
   no adapter detected for workspace 'tools', skipping
   ```

   Expected result: Either the warning disappears after you pin an adapter, or you accept the directory is intentionally excluded.

## Verify it worked

Run `diataxis plan` and inspect .diataxis/plan.json: reference page slugs should reflect each workspace's directory structure, and no "no adapter detected" warning should appear for a directory you expect to be documented. Running `diataxis generate --mode reference` should then produce pages grouped by the workspace names you set, not by the bare directory path.

## Related

- [explanation/language-adapter-architecture](../explanation/language-adapter-architecture.md)
- [tutorials/write-a-language-adapter](../tutorials/write-a-language-adapter.md)
- [how-to/review-and-edit-the-page-plan](../how-to/review-and-edit-the-page-plan.md)
- [reference/lib/adapters](../reference/lib/adapters.md)

