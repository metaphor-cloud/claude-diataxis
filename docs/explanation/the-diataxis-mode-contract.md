---
title: "The Diataxis mode contract"
slug: explanation/the-diataxis-mode-contract
mode: explanation
generated_by: diataxis
generated_at: 2026-07-29T21:05:59Z
frozen: false
---

# The Diataxis mode contract

In this harness a Diataxis mode is not a label attached to a finished page but the type that selects its prompt, its schema, its renderer, its model and its staleness hash, which is why mode is decided once in the plan, why reference pages bypass the model entirely, and why a how-to handed two goals refuses to write itself.

## Mode is a type, not a label

Read `claude_run` and you find that a mode string is a lookup key. It resolves to a system prompt under `prompts/system/`, a task template under `prompts/task/`, a JSON Schema under `schemas/`, and a model plus effort level from the config's `models` block (`lib/claude.sh`, lines 38-46). The same string then picks a renderer: `render_page` dispatches on it and dies if no renderer exists for the mode it was handed (`lib/render.sh`, lines 125-138). And `compute_inputs_hash` folds the mode's system prompt, task template and schema into the page's `inputs_hash` (`lib/manifest.sh`, lines 63-81), so editing `prompts/system/tutorial.md` makes every tutorial stale and touches nothing else.

That is four independent pipelines that happen to share a driver, and it is the real reason a page carries exactly one mode. No schema accepts both a tutorial's `steps` with their `checkpoint` fields and an explanation's `thesis` plus `tradeoffs` table. `render_page` cannot run two renderers over one payload. A hybrid page has nowhere to live in the data path, so single-mode is not an editorial preference the prompts request politely, it is the only shape the harness can represent. The prompts do state the rule, because the model has to know what it is aiming at, but the enforcement is structural.

Mode also survives onto disk. `render_frontmatter` writes `mode:` into the YAML frontmatter of every generated page (`lib/render.sh`, lines 9-21), which is what the audit pass reads back when it needs to know what a page claims to be.

## The plan is where mode gets decided, and the only place

`diataxis plan` writes no prose, and `diataxis generate` writes no page that is not in the plan. The plan pass is told, in its own system prompt, that mode confusion is the single most common documentation failure and that the plan is where it gets prevented (`prompts/system/plan.md`, line 5). Its output schema then constrains each entry to one of four mode values and forces the slug into one of four matching directories (`schemas/plan.json`, lines 12-20).

Those two constraints are independent, so the harness checks their agreement itself. After the plan call returns, `cmd_plan` scans the model's pages for a slug whose prefix contradicts its `mode` and dies on the first one it finds (`bin/diataxis`, lines 476-486). A schema pattern can require that a slug starts with `how-to/`; it cannot require that it does so precisely when `mode` is `howto`.

Encoding mode twice, once in the field and once in the directory, looks like duplication and is deliberate. `mode_to_dir` and `dir_to_mode` are the two halves of that redundancy (`bin/diataxis`, lines 131-149), and the second half earns its keep during audit: when a page on disk has no `mode:` in its frontmatter, which is the normal case for a hand-written page, the audit pass falls back to inferring the mode from its directory so it still has a rubric to apply (`bin/diataxis`, lines 1006-1012). Generated pages assert their mode; adopted pages get a guess.

## Reference pages are derived, not judged

`derive_reference_pages` groups the adapter symbol inventory by module directory and emits one page per module, mirroring the source tree, with the rationale string "derived mechanically from the symbol inventory" (`bin/diataxis`, lines 413-435). The plan model is told not to propose reference pages at all, and to treat the derived slugs it is given as coverage information only (`prompts/system/plan.md`, lines 16-20). The harness does not rely on that instruction: it filters the model's output with `select(.mode != "reference")` before merging, so a model that ignores the rule cannot add a reference page or displace a derived one (`bin/diataxis`, lines 476-488).

The reasoning is that reference completeness is a countable property of something the harness already has. The adapters produce a symbol inventory; the set of modules is a `group_by` over it. Asking a model to enumerate modules from a file listing gets you a plausible list that quietly omits a package and hallucinates one that was deleted, and you would then have no way to tell. The mechanical derivation also makes the plan reproducible enough to compare against golden fixtures in the test suite, which a model-authored inventory would never be. This is recorded as decision 6 in the README (lines 306-311).

The cost is that derived entries carry fixed editorial weight: every one gets `priority: 2` and `audience: "developer"`, because there is no mechanical signal for which module matters most to a reader. Mechanical derivation is also why the corresponding audit rule is free. `missing_reference` compares public inventory symbols against the symbols recorded on reference pages in the manifest, entirely locally, with no model call (`bin/diataxis`, lines 979-996).

One wrinkle: `reference_bulk` is not a fifth mode. It is a model routing decision inside the reference mode, taken when a page has 25 or more inventory symbols, and `claude_files_mode` collapses it back to the reference prompt and schema (`bin/diataxis`, lines 599-614). Converting an already-extracted symbol list to prose is cheap work; the contract it writes against is identical.

## A two-goal how-to returns a split instead of a page

The how-to schema does not describe a page. It describes a `result` that is either a page or a `split`: an array of at least two slug and title pairs, each slug matched against `^how-to/[a-z0-9][a-z0-9/-]*$` (`schemas/howto.json`, lines 8-120). The system prompt tells the generator that if the page it was asked for actually contains two or more distinct goals, it should not write the page and should return the split instead (`prompts/system/howto.md`, lines 7-8).

This is refusal expressed as data rather than as prose the harness would have to parse. `generate_one_page` unwraps the `result` field, tests for `has("split")`, and records `status: "split"` instead of rendering Markdown (`bin/diataxis`, lines 626-646). The parent then rewrites `.diataxis/plan.json`, replacing the offending entry with one entry per goal, each inheriting the original's sources, priority and audience and carrying the rationale "split from <slug>: one goal per how-to", warns the operator, and leaves the pages for the next `generate` (`bin/diataxis`, lines 733-748). Splits are counted separately from failures and do not make the run exit non-zero.

The alternative was to let the model write the sprawling page and rely on the audit pass to flag `mode_mixing` afterwards. The split wins because it repairs the plan, and the plan is the artifact that persists. Fixing one page fixes one page; fixing the plan entry fixes every run after it. There is also a small implementation scar worth knowing about, since it explains the otherwise pointless `result` wrapper: the API rejects a `oneOf` at the top level of a tool input schema, so the branch had to be nested one level down.

The `result` unwrap runs before the split test, and both run before citation verification, so a split never gets its citations checked. There are none to check.

## Three tutorials is a warning, not an error

The plan prompt says a repository should have one to three tutorials and to never propose more (`prompts/system/plan.md`, line 18). After merging derived and model pages, the harness counts tutorials in the result and, above three, warns and tells you to review `.diataxis/plan.json` before generating (`bin/diataxis`, lines 490-493). It does not die, which is the interesting part, because a slug that contradicts its mode does die a dozen lines earlier.

The asymmetry tracks a real difference. A slug and mode that disagree have no valid interpretation; something is wrong and no downstream step can proceed sensibly. Four tutorials is a claim about a repository, and it can be right. A monorepo with four workspaces plausibly wants a first-run lesson per workspace. The harness has no way to know, so it flags and defers to you.

There is a spend argument reinforcing the editorial one. Tutorials are the most expensive pages the harness produces: Opus at high effort by default (`lib/config.sh`, lines 17-25), plus a verification pass that executes every fenced block and, on failure, spends further repair calls. An inflated tutorial count is a budget problem as well as a Diataxis problem, and both are cheapest to fix in a plan diff. That is also why the warning names the file rather than describing the problem abstractly: `plan.json` is committed, diffable and reviewable, and a human reading that diff is the last check in the chain.

## Four rings of enforcement

The mode contract is enforced four times over, at decreasing strength and increasing cost.

The system prompts state the rules. This ring is advisory: a model can ignore it, and the harness assumes it sometimes will.

The schemas make violations unrepresentable. Every call passes `--json-schema` and the harness reads `.structured_output`, never the free-text `.result`. When nothing schema-conforming comes back, `generate_one_page` records `status: "failed"` with an explicit error rather than salvaging prose, so a page that breaks its mode's shape does not reach disk in a degraded form.

The harness checks what schemas cannot express: that slug and mode agree, that reference pages come only from derivation, that the tutorial count is sane, that a split amends the plan. These are relational or cross-page properties, invisible to a per-response validator.

The audit pass catches content that satisfies all three rings and still mixes modes. Its rubric names `mode_mixing` (explanation prose inside a tutorial, numbered steps inside an explanation, motivation inside reference material) and `title_not_task_shaped` for a how-to titled as a noun phrase (`prompts/system/audit.md`, lines 9-14). Both need judgment, so both cost a model call, and that is why they live in `diataxis audit` rather than in `diataxis check`. The gate that runs on every pull request stays free and deterministic by default, computing only the local rules; `audit.model_audit_in_check` opts the judgment rules into continuous integration for teams willing to pay for them.

Read in that order the design is consistent: push each rule to the cheapest ring that can actually hold it, and never let a ring above pretend to enforce something it cannot.

## Tradeoffs

| Decision | Chose | Rejected | Because |
| --- | --- | --- | --- |
| Where a page's mode is assigned | Once, in the plan pass, cross-checked against the slug directory before the plan is written | Letting the generation pass choose or revise a page's mode | Mode selects the prompt, schema, renderer and inputs hash, so a mode change mid-generation would invalidate the page's identity and its manifest entry |
| How the reference page inventory is produced | Mechanical derivation from the adapter symbol inventory, one page per module, with model-proposed reference pages filtered out | Letting the plan model propose reference pages alongside the other three modes | Coverage is a countable property of the inventory the adapters already produce; a model both omits real modules and invents absent ones, and derived entries keep plan.json comparable against golden fixtures |
| What happens when a planned how-to contains two goals | The generator returns a structured split and the harness amends plan.json | Writing the sprawling page and letting the audit pass report mode_mixing later | The plan is the durable artifact; correcting it fixes every subsequent run instead of one page |
| Response to a plan wanting more than three tutorials | A warning naming .diataxis/plan.json for human review | Failing the plan run | The limit is editorial judgment about a repository, not a violation of the data contract, and a multi-workspace monorepo can legitimately justify more |
| Encoding mode in both a field and a directory prefix | Redundant encoding with a hard agreement check | Deriving mode from the slug directory alone | Generated pages need an explicit assertion the harness can contradict, while hand-written pages with no frontmatter still need dir_to_mode to guess a rubric |
| Where the judgment-based mode rules run | In diataxis audit by default, in check only when audit.model_audit_in_check is set | Running mode_mixing and title shape checks in every continuous integration run | The pull request gate must stay free and deterministic; a model rule in that path makes it cost money and vary between runs |

## Open questions

- Nothing verifies related links against the plan. The schemas require each related entry to carry a slug and a mode, but no harness check confirms that the target page exists or that its recorded mode matches the mode claimed at the link site, so a link can assert the wrong mode indefinitely.
- The split escape hatch is how-to only. A tutorial covering two unrelated artifacts, or an explanation carrying two theses, has no structured way to refuse; only the audit pass's mode_mixing rule notices, and only after the page is written.
- Derived reference entries fix priority at 2 and audience at "developer", and they are re-derived on every plan run before the merge, so hand edits to a reference entry's editorial weight do not survive the next plan.
- The four modes are hardcoded in several places at once: mode_to_dir, dir_to_mode, the plan schema enum, the render_page dispatch, and the prompts and schemas directories. Adding a mode is a code change rather than configuration. That matches Diataxis having exactly four quadrants, but it means a repository wanting a fifth kind of page has no supported path.
- prompt_version_for gives each mode an independent version counter, but nothing yet uses per-mode bumps in anger. Whether a prompt edit should invalidate every page of that mode, or only pages whose content the edit could plausibly change, is unresolved and currently answered with the blunt option.

## Related

- [explanation/why-the-harness-owns-the-filesystem](../explanation/why-the-harness-owns-the-filesystem.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [explanation/tutorial-verification-and-repair](../explanation/tutorial-verification-and-repair.md)
- [explanation/audit-versus-check](../explanation/audit-versus-check.md)
- [explanation/model-routing-and-cost](../explanation/model-routing-and-cost.md)
- [how-to/review-and-edit-the-page-plan](../how-to/review-and-edit-the-page-plan.md)

