---
title: "Staleness, idempotency and the manifest"
slug: explanation/staleness-idempotency-and-the-manifest
mode: explanation
generated_by: diataxis
generated_at: 2026-07-29T21:04:52Z
frozen: false
---

# Staleness, idempotency and the manifest

The manifest tracks two independent questions behind two independently-computed hashes, inputs_hash for "did anything feeding the model call change" and content_hash for "did a person change what the harness wrote", and that separation, not the hashing itself, is what lets a committed manifest turn a second run into a verified no-op instead of a guess.

## Two hashes, two different questions

`.diataxis/manifest.json` holds one entry per generated page, and two of its fields are easy to conflate because both are `sha256:`-prefixed strings sitting next to each other in the same JSON object. They answer different questions and are consulted by different code paths.

`inputs_hash` is a fingerprint of everything that goes into the model call. `page_is_stale` recomputes it for a page and compares it against the value recorded on that page's manifest entry: no entry at all counts as stale, and a mismatch counts as stale. That is the whole rule; it says nothing about what is on disk.

`content_hash` is a fingerprint of the bytes the harness itself last wrote. `page_disk_status` recomputes the digest of the file on disk and reports one of four states: `absent`, `clean` when it still matches the recorded digest, `edited` when it differs, and `unknown` when the file exists but the manifest entry has no `content_hash` at all.

Keeping these separate is what lets both facts be true about the same page at once. A page can have drifted inputs (its source file changed) while its on-disk content still exactly matches what was last generated from the old inputs, in which case it is stale but clean, and safe to regenerate. Or a page can have unchanged inputs while a person hand-edited the file afterward, in which case it is fresh but edited, and regenerating it would destroy work with no other copy. A single hash covering both facts could not represent the second case at all: it would either look stale (a false positive that discards the edit) or look clean (silently reverting on the next regeneration). Splitting the check into two independent functions, `page_is_stale` and `page_disk_status`, is what makes the deadlock case in the next section representable instead of averaged away.

## What compute_inputs_hash covers, in stable order

`compute_inputs_hash` does not hash a concatenation of file bodies; it builds a labeled text stream, one line per covered input, and digests that stream through `sha256_stream`. The labeling matters more than it looks: it means the digest stays legible if you ever need to reproduce it by hand, because each line names what it covers before the colon-separated hash.

The stream carries, in order: one `src:<path>:<hash>` line per source path listed for the page (sorted with `LC_ALL=C sort` so reordering the `sources` array in the plan does not restale a page on its own), then the mode's system prompt file, the mode's task template, the mode's JSON Schema, the effective `models` configuration block, and the page's own plan entry as JSON. Any change to any one of these produces a different digest, and `page_is_stale` reports the page as needing regeneration.

Two details are worth calling out. First, a source path that no longer exists on disk hashes to the literal string `src:<path>:missing` rather than aborting the run, so deleting a source restales the page instead of failing the whole `generate` invocation, and restoring the file restores the previous digest. Second, the path itself is embedded in the hashed line alongside the file's digest, so renaming a source restales the page even when its bytes are byte-for-byte identical. That is deliberate: the citations inside a generated page point at specific paths, and a rename breaks those citations regardless of whether the content moved with the file.

The `models` line hashes the entire configured models block for every page, not a per-mode slice of it. Changing the how-to model in config restales the explanation pages too, and upgrading the vendored harness to a release that changes default routing restales the entire manifest. That is coarser than it needs to be for any single page, and it is the price of not maintaining a per-mode invalidation map that would need to track escalations like the `reference_bulk` symbol-count threshold as a separate fact.

## How a committed manifest makes a second run do nothing

`cmd_generate` never generates from the plan directly. For every plan page that survives `--mode`/`--page` filtering, it applies three gates in a fixed order, and a page that clears none of them never reaches the queue: frozen first (`page_is_frozen`, checked before anything else so it wins unconditionally), then disk status (an `edited` or `unknown` file is skipped with a warning unless `--force` is given), then staleness (`compute_inputs_hash` recomputed and compared with `page_is_stale`, skipped when the file is present and the hash matches). Only a page that fails all three gates gets appended to the run's queue; everything else increments a skip counter.

When that queue ends up empty, `generate` prints `generate: nothing to do (N up to date or skipped)` and exits zero without invoking `claude` at all. That is the literal mechanism behind the README's idempotency claim: the harness computes hashes and reads a JSON file, it does not need to remember anything about a previous run's process state.

The manifest being committed to the repository is what turns that into a property of the branch rather than a property of one developer's machine. Continuous integration clones the same manifest alongside the same docs tree, recomputes the same digests over the same files, and reaches the identical verdict a contributor's laptop reached, with no warm cache and no shared state beyond git. Writes into it happen only in the parent process: `manifest_write` renders through `jq` into a process-suffixed temp file and renames it into place, and `manifest_upsert_page` re-sorts by slug so the committed file diffs cleanly between runs. Under `--concurrency`, worker subshells write only into a scratch directory; the parent applies every manifest update and every repository write serially, because an atomic rename makes one write safe, not concurrent writes from several workers into the same file.

## Reading the skip messages correctly

Three distinct reasons produce a skip, and only one of them is worth a warning; conflating them is the most common way to misread a `generate` run.

A frozen page skips silently at verbose level with `skip <slug>: frozen`. `page_is_frozen` reads the flag from either the manifest entry or a `frozen: true` frontmatter key, and because it runs first, a frozen page is never regenerated, never touched by `--force`, and never removed by `clean` either.

An edited-or-unrecorded page skips with an actual warning: `skip <slug>: <path> exists with changes diataxis did not generate`. This message covers both the `edited` and `unknown` disk states identically, treating a file that exists with no recorded provenance exactly like a deliberate hand edit, and naming both escape hatches in the same line: `--force` to overwrite once, or `frozen: true` to keep it for good.

An up-to-date page skips at verbose level with `skip <slug>: up to date`, and the condition behind it is easy to miss: the gate also requires the file to still exist on disk (`_disk != absent`). Delete a generated page but leave its manifest entry untouched, and the next `generate` regenerates it, because a matching `inputs_hash` over a file that is not there is not a reason to do nothing.

The frozen and up-to-date skips are `verbose`-gated; the warning for edited/unknown pages is not. A run reporting `N skipped` in its default output collapses all three counts into one number, so the count alone tells you nothing about which kind of skip happened. Re-run with `--verbose` to see the breakdown.

## Why check's stale finding is broader than a hash mismatch

`local_findings` (the deterministic rule set `check` runs without a model call) emits a finding with `rule: stale` for three distinct situations, and `cmd_check` sums them into one count before deciding whether to exit non-zero. The first is a page present in the plan with no manifest entry, or no file on disk: reported as never generated. The second is the case this page has mostly discussed, a genuine `inputs_hash` mismatch computed the same way `generate` computes it. The third is model divergence: every manifest entry records both `model_requested` and `model_used`, and when `models_equivalent` (which forgives only a trailing eight-digit date suffix, so a genuine model swap still counts) says the two disagree, the page is marked stale because the requested model's Opus-tier call overloaded and its configured Sonnet fallback answered instead.

So a `stale` finding in a `check` report does not always mean a source file changed underneath the page; the `suggestion` text on the specific finding is what tells you which of the three cases you actually hit. This is also the mechanism behind a report going red on a page nobody touched: an overloaded API silently downgraded the model on whatever run produced that page, and the divergence surfaces on the next `check` rather than at generation time.

A sharp edge follows from the two systems disagreeing about frozen versus edited pages. `local_findings` skips frozen pages entirely but does not special-case edited ones, while `cmd_generate` refuses an edited page before it ever computes a hash. Hand-edit a generated page, then change one of its listed sources, and you get a stable deadlock: `check` reports the page stale and fails the pipeline, while `generate` declines to touch it without `--force`. Resolving it means making the page's status explicit, either freezing it so both commands leave it alone, or regenerating with `--force` and accepting the loss of the hand edit.

## What the hash deliberately does not cover

Naming what falls outside `inputs_hash` is more useful than implying the coverage is exhaustive.

Voice conventions are appended to a copy of the system prompt in a temporary directory, keeping `prompts/system/<mode>.md` itself pristine; `compute_inputs_hash` hashes that pristine file directly. Switching `voice.style_guide` between `google` and `microsoft` changes every future prompt sent to the model, and restales nothing already generated. That change reaches existing pages only through `--force`.

The `prompt_version` string, built by `prompt_version_for` from the `PROMPT_VERSION_TUTORIAL`/`_HOWTO`/`_REFERENCE`/`_EXPLANATION` constants, is recorded on every manifest entry and read by nothing in the staleness path. `page_is_stale` compares only `inputs_hash`. Because the prompt file's content is already hashed directly, bumping one of those constants without also editing the corresponding prompt bytes leaves every recorded `inputs_hash` unchanged, so no page restales. The comment above the constants promises that bumping a mode's version invalidates every page of that mode; the code as it stands does not keep that promise unless the bump is accompanied by an edit to the prompt file itself.

The symbol-extraction strategy adapters record on each inventory entry (native tooling versus a grep fallback) also sits outside every hash. Installing `griffe` or `typedoc` on a machine that previously fell back changes what a reference page's model call sees, without changing anything `compute_inputs_hash` covers, so no reference page restales when the underlying tooling improves.

## Tradeoffs

| Decision | Chose | Rejected | Because |
| --- | --- | --- | --- |
| How to detect that a page's inputs have moved | Content digests of an explicit, named input list, recorded in a manifest committed to the repository | File modification times, or a comparison against git history | Modification times do not survive a fresh clone, so CI would treat every page as changed on every run. A git-history comparison needs a merge base a detached CI checkout may not have, and still cannot represent non-file inputs like the effective models configuration block. |
| Whether one hash can serve both freshness and edit protection | Two fields, `inputs_hash` and `content_hash`, checked by two separate functions (`page_is_stale`, `page_disk_status`) | A single combined hash covering both inputs and generated output | Drifted inputs and a human edit demand opposite responses, regenerate versus stop and ask, and a page can be in both states at once. One hash cannot express "stale and protected" simultaneously, which is exactly the state a hand-edited page with newly-changed sources occupies. |
| Granularity of the models configuration inside the inputs hash | Hash the entire merged `models` block once, for every page regardless of mode | Hash only the model and effort setting for the page's own mode | Per-mode hashing needs an invalidation map that stays correct as routing grows, including conditional escalations like the `reference_bulk` threshold. A single coarse hash over-invalidates on unrelated routing changes but fails safe; a narrower hash risks under-invalidating and shipping prose generated under a model the config no longer selects. |
| How to treat a file that exists on disk with no recorded `content_hash` | Report disk status `unknown` and gate it in `cmd_generate` exactly like an `edited` file: skipped with a warning, requiring `--force` or `frozen: true` | Treat an unrecorded file as harness output and overwrite it | The likeliest explanation for an untracked file already sitting in the docs tree is that a person wrote it by hand. Guessing wrong in the overwrite direction destroys work with no other copy; guessing wrong in the refuse direction costs one `--force`. |
| Where the manifest lives | Committed at `.diataxis/manifest.json`, sorted by slug, written through an atomic rename | An ignored local cache directory, or state kept only in a CI cache key | A committed manifest makes freshness a reviewable property of the branch: the pull request diff shows exactly which pages regenerated and what they cost, and `check` reaches the same verdict on any clone without a warm cache. Slug sorting keeps the resulting merge conflicts limited to pages both branches actually touched. |

## Open questions

- The PROMPT_VERSION_* constants and prompt_version_for are recorded on every manifest entry but page_is_stale never reads them, so bumping a version constant without touching prompt bytes restales nothing, contradicting the comment above the constants in bin/diataxis. Either fold the version string into compute_inputs_hash, or drop it as metadata the harness does not act on.
- Should compute_inputs_hash digest the merged system prompt, voice conventions included, rather than the pristine prompts/system/<mode>.md file? That would restale every page whenever voice.style_guide changes, arguably the correct behavior, at the cost of a mass regeneration triggered by a style-only edit.
- Reference pages depend on which extraction strategy the adapter used (native tooling versus a grep fallback), and that strategy is not part of any hash. Installing native tooling upgrades the inventory a reference page is built from without restaling a single page; folding the recorded strategy into the reference-mode hash would close this, at the cost of making the hash depend on what happens to be installed on the machine that runs it.
- No merge driver ships for .diataxis/manifest.json. Slug sorting keeps conflicts local to pages both branches regenerated, but resolving those conflicts by hand still means reconciling hashes, costs and timestamps across branches, which is exactly the kind of edit a person is ill-suited to make correctly.
- Model divergence is folded into the same `stale` rule as a genuine source change, so a team cannot currently choose to tolerate Opus-to-Sonnet fallback output while still failing check on real input drift; a distinct finding rule would let those two cases carry different severities.

## Related

- [explanation/why-the-harness-owns-the-filesystem](../explanation/why-the-harness-owns-the-filesystem.md)
- [explanation/audit-versus-check](../explanation/audit-versus-check.md)
- [explanation/reproducibility-and-bare-mode](../explanation/reproducibility-and-bare-mode.md)
- [explanation/model-routing-and-cost](../explanation/model-routing-and-cost.md)
- [how-to/gate-pull-requests-on-documentation-freshness](../how-to/gate-pull-requests-on-documentation-freshness.md)
- [how-to/protect-hand-written-pages-from-regeneration](../how-to/protect-hand-written-pages-from-regeneration.md)
- [how-to/regenerate-a-single-page](../how-to/regenerate-a-single-page.md)
- [how-to/remove-generated-pages-that-left-the-plan](../how-to/remove-generated-pages-that-left-the-plan.md)
- [how-to/control-spend-with-a-budget](../how-to/control-spend-with-a-budget.md)

