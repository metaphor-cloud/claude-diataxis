---
title: "Model routing and cost"
slug: explanation/model-routing-and-cost
mode: explanation
generated_by: diataxis
generated_at: 2026-07-29T21:39:21Z
frozen: false
---

# Model routing and cost

The harness routes each generation mode to a model by the kind of judgment that mode demands rather than by how much text it emits, and it treats every deviation from that routing (a family alias resolving elsewhere, a fallback engaging, a budget running out mid-call) as a fact worth recording and failing on rather than absorbing quietly.

## Routing follows judgment, not word count

The shipped routing table lives in one place, `config_default_json`, and reads as a statement about difficulty rather than volume (`lib/config.sh:17-26`). Planning, tutorials and explanation pages go to `claude-opus-5` at high effort. How-to guides, reference pages and the audit pass go to `claude-sonnet-5` at medium effort. The bulk reference pass goes to `claude-haiku-4-5` with no effort setting at all.

The reasoning behind that split is worth stating plainly, because output length would suggest almost the opposite assignment. A reference page can be the longest artifact the harness produces and is still the least demanding: the symbol inventory has already been extracted by an adapter, signatures and doc comments are handed over as structured input, and the model's task is to arrange known facts. A tutorial is short by comparison and much harder: it must invent a plausible starting state, order steps so each one works, and produce commands that survive execution in an empty directory, because the harness will run them. An explanation page is harder again, since nothing in the repository states which tradeoffs were made or which alternatives were rejected. Planning sits at the top because a bad plan is the one error that propagates into every page downstream.

Effort is part of the same decision rather than a separate dial. `cfg_effort` returns an empty string when a mode's entry omits the key, and `claude_run` only appends `--effort` when the lookup produced something (`lib/claude.sh:66-68`). That is why the bulk reference entry has no effort field: an unset value is honest about the fact that nobody wants extended reasoning applied to a signature-to-prose transformation, whereas writing `"effort": "low"` would be a claim that low effort was measured and chosen. The absence is the design.

Routing is also the one config value with no usable default at call time. When `cfg_model` returns nothing for a mode, `claude_run` fails with the config exit code rather than picking something reasonable (`lib/claude.sh:45-48`). A harness that silently substituted a model would produce prose whose provenance nobody could reconstruct.

## The bulk reference pass and where the boundary sits

Reference is the only mode that routes dynamically. When a reference page's filtered symbol inventory has 25 or more records and a `reference_bulk` model is configured, the call mode switches (`bin/diataxis:608-613`). Everything else about the call is unchanged: `claude_files_mode` maps `reference_bulk` back to the reference system prompt, task template and schema, so the two routes share one contract and cannot drift apart in what they produce (`lib/claude.sh:8-13`).

The threshold of 25 is a judgment call, not a measurement, and it is the sort of number that deserves to be admitted as such. The intuition is that a large already-extracted symbol list is dominated by mechanical restatement, while a small module page still requires deciding what matters and what to omit. Nothing in the repository validates the boundary. What does exist is a safety property: the switch is conditional on `cfg_model reference_bulk` returning a value, so deleting the entry from the config disables bulk routing entirely and every reference page goes back to the reference model. Opting out costs one key.

One consequence of the dynamic route reaches the manifest. `model_requested` is recorded from `cfg_model "$_call_mode"`, meaning the bulk model, not the nominal mode's model (`bin/diataxis:702-703`). Divergence detection therefore compares the answer against what was actually asked for, which is the only comparison that means anything.

## Exact model ids, and what an alias would cost you

The README states the rule: use exact model ids in config, not family aliases, so output does not shift when a new family member ships (`README.md:113-116`). The stronger argument is structural, and it lives in `models_equivalent` (`bin/diataxis:327-337`). That function treats two ids as the same only when they match outright or differ by a trailing eight-digit date suffix, which is exactly the tolerance needed for a dated snapshot of a model you named without a date.

An alias falls outside that tolerance. Configure a family alias and the application programming interface (API) resolves it to a concrete dated id, `claude_model_used` reads that concrete id back out of the `modelUsage` breakdown (`lib/claude.sh:145-155`), and the comparison against the alias you requested fails. Every page you generate is then reported as diverged, forever, until you edit the config. Exact ids are not a stylistic preference here: they are the only inputs for which the harness's own equivalence check can return true.

The dated-suffix tolerance is itself a deliberate loosening. Without it, a run whose id resolved to a snapshot would look like a fallback event, and staleness would fire on a difference nobody caused and nobody can act on. With it, a genuine substitution still stands out.

## Fallback buys availability and spends determinism

Opus calls carry `--fallback-model` sourced from `.models.fallback` so an overloaded frontier model does not kill a forty-page run (`lib/claude.sh:72-74`). Note how the attachment is decided: the case pattern matches the model string for `opus`, not the mode name. Route how-to guides at an Opus model and they inherit the fallback; route explanation pages at Sonnet and they lose it. The flag follows the model, which is the right coupling, since overload resilience is a property of the model being called and not of the documentation mode.

The interesting decision is what happens afterwards. A fallback that engaged means a page was written by a cheaper model than the routing table specified, and the whole premise of routing by judgment is that this matters. So the concrete model that answered is recorded per page, `generate` warns as soon as it notices (`bin/diataxis:764-766`), and `check` emits a `stale` error finding with severity `error` and the excerpt naming both ids (`bin/diataxis:933-939`). Continuous integration (CI) fails on it. The alternative, accepting the page because it validated against the schema and its citations resolved, would mean the routing table describes an intention rather than a guarantee.

That choice has a rough edge worth being honest about. Divergence is recorded in the manifest, but the page's `inputs_hash` is current, so `page_is_stale` returns false and the next `generate` skips the page as up to date (`bin/diataxis:803-808`). `check` fails and `generate` declines to fix it; regenerating requires `--force`. The warning text says the page "is marked for regeneration", which overstates what the manifest actually causes to happen.

Fallback is also not applied recursively or guarded against itself. `.models.fallback` is read as a plain string with no relationship to the primary model (`schemas/config.json:38`), so a config naming an Opus model as the fallback for Opus calls is accepted, and nothing detects the resulting pointlessness.

## Cost is enforced twice and accounted once

Spend control is deliberately layered. Before every call the harness refuses to start when accumulated run spend has reached the budget, naming the work left undone instead of half-generating (`lib/manifest.sh:145-152`). Then the same remaining figure is passed to the process as `--max-budget-usd` (`lib/claude.sh:76-79`), so a single runaway call cannot overshoot even though its cost was unknowable in advance. The README records the reasoning as decision 13 (`README.md:325-327`).

The second belt has a failure mode the harness handles explicitly rather than leaving to a reader's guesswork: when the per-call cap stops a call, the process can exit non-zero with nothing on standard error. So the error path checks for exactly that shape, empty output plus a budget in play, and appends a hint naming the remaining and total amounts (`lib/claude.sh:117-119`). Model-permission and budget errors are classified into their own exit codes before the generic path runs (`lib/claude.sh:108-115`), because "model unavailable" and "out of money" call for different fixes.

After each call, `total_cost_usd` from the result is added to run spend (`lib/claude.sh:128`) and lands in the page's manifest entry, which makes `diataxis cost` able to group lifetime spend by the model that actually answered rather than the one requested (`bin/diataxis:1134-1136`). That grouping is the audit trail for fallback: a run where Opus was requested throughout but Sonnet appears in the by-model breakdown is a run that got cheaper prose than it asked for.

Two places make cost larger than the routing table suggests. Tutorial repair calls route back to the tutorial model at 12 turns each, up to `verify.max_repairs` times, and their cost accumulates into the page's total (`bin/diataxis:664-676`), so the mode that is most expensive per call is also the only one that can call more than once. And under concurrency the two belts loosen: `budget_require` runs for each page as the batch is spawned, but `budget_add` only runs in the parent after `wait` (`bin/diataxis:836-861`, `bin/diataxis:729`). A batch of four workers therefore each see the same remaining budget and each receive it as their own per-call cap, so a run can exceed its budget by roughly the size of one batch before the next check notices.

The routing block is also an input to staleness. `compute_inputs_hash` folds a hash of the entire `.models` object into every page's inputs hash (`lib/manifest.sh:78`), so editing any model or effort value marks every page stale. That is a large blast radius from a small edit, and it is intended: if which model wrote a page matters enough to fail CI over, it matters enough to invalidate pages written under the old routing.

## Why Fable-tier models are refused, and why the refusal is only prose

The README rules out Fable-tier models on price and fit: roughly double the Opus cost with no benefit for this workload (`README.md:113-116`). The workload argument is the substantive one. The hardest thing the harness asks of a model is reading a mid-sized codebase through Read, Grep and Glob and forming a defensible account of it. Nothing in the pipeline resembles the long-horizon autonomous work that a more expensive tier exists to serve, and every call is capped at 24 turns (`bin/diataxis:618`) with the filesystem owned entirely by the shell, so there is no room for a model to spend its advantage even if it had one here.

What is notable is where that refusal is not enforced. `model_entry` in the config schema constrains `effort` to an enum but accepts any string as a model id (`schemas/config.json:72-80`), and `config_load` performs no id validation. Point a mode at any model you like and the harness will call it. The only live verification is `probe_models`, which sends a one-word prompt to each unique configured id and fails with the model-unavailable exit code when the account cannot reach it (`lib/preamble.sh:305-322`), and that probe runs from `doctor` only when `DIATAXIS_LIVE=1`, because `doctor` executes inside every subcommand and must stay fast and free (`bin/diataxis:356-360`, recorded as decision 7 at `README.md:311-313`).

The refusal is therefore advice to a reader, not a constraint on a run. That is a defensible position for vendored code: an allowlist of permitted ids baked into a directory that gets committed into other people's repositories would start rejecting valid models the moment a new family shipped, and would present to those users as a bug in the harness rather than as a stale list. The cost of the position is that a config typo pointing at an expensive model produces no warning until the bill arrives, and the model-permission probe that would have caught an unreachable id is off by default.

## Tradeoffs

| Decision | Chose | Rejected | Because |
| --- | --- | --- | --- |
| How modes map to models | Route by the judgment a mode requires: Opus for planning, tutorials and explanation, Sonnet for how-to, reference and audit, Haiku for the bulk reference pass | Routing by expected output length, or one model for every call | reference pages are long but mechanical once an adapter has extracted the symbol inventory, while tutorials are short and must survive execution, so length is close to inversely correlated with the difficulty that model choice actually addresses |
| What a mode's model entry may omit | Treat a missing effort key as "send no effort flag", and treat a missing model as a fatal config error | Defaulting effort to low and defaulting the model to a sensible family member | an unset effort honestly says nobody tuned it, while a defaulted model would let a run produce prose whose provenance cannot be reconstructed from the config |
| Model ids in config | Require exact dated-or-undated ids, tolerating only a trailing eight-digit date suffix when comparing requested against used | Accepting family aliases and resolving them at call time | an alias resolves to a concrete id that models_equivalent can never match, so every generated page would be reported as diverged forever, while the date tolerance still lets a genuine substitution stand out |
| What happens when the Opus fallback engages | Record the concrete model that answered, warn during generate, and emit a stale error finding in check so continuous integration fails | Accepting the page because it validated against the schema and its citations resolved | if routing by judgment is a real design claim then a page written by a cheaper model than specified is not the artifact that was asked for, and silently accepting it would reduce the routing table to a statement of intent |
| Where model routing sits in the staleness calculation | Hash the entire models block into every page's inputs hash | Hashing only the calling mode's entry, or excluding routing from the hash | a large blast radius from a small config edit is the correct behavior when which model wrote a page is important enough to fail continuous integration over |
| How budget limits are enforced | Refuse to start a call once accumulated run spend reaches the budget, and pass the remaining amount per call as a second cap | Estimating each call's cost in advance and reserving against it | call cost is unknowable before the call, so refusing to start plus a hard per-call ceiling bounds the overshoot without pretending to a prediction, and completed pages are already in the manifest so the run resumes |
| How expensive model tiers are kept out | A documented refusal plus an opt-in live probe of configured ids, with no id validation during config load | An allowlist of permitted model ids enforced by the config schema | a hard allowlist inside a directory that gets vendored into other repositories would reject next year's models and read to those users as a harness bug, though the cost is that a typo pointing at an expensive model produces no warning |
| When model permissions are verified | Probe each configured id live only from doctor with DIATAXIS_LIVE=1 | Probing on every subcommand, since doctor already runs inside all of them | the preamble must stay fast and free, and paying for one round trip per configured model before every generate or check would make the cheapest command in the harness cost money |

## Open questions

- The 25-symbol threshold for bulk reference routing is an intuition, not a measurement. Nothing in the repository compares Haiku and Sonnet output on reference pages just above and below the boundary, so the number could be wrong in either direction.
- Fallback divergence fails check but does not make generate redo the page: the inputs hash is still current, so the page is skipped as up to date and only --force regenerates it. The generate warning claims the page "is marked for regeneration", which the manifest does not actually cause.
- Under concurrency the budget can be exceeded by about one batch, because budget_require reads run spend as workers are spawned while budget_add only runs in the parent after wait, and each worker receives the same remaining figure as its own per-call cap. Whether workers should reserve against a shared file or the batch size should bound the check is unresolved.
- The fallback model is an unconstrained string with no relationship to the primary model, so naming an Opus model as the fallback for Opus calls is accepted and produces no warning.
- Nothing records the claude CLI version that resolved a model id into a dated snapshot. Two machines with the same config and manifest can therefore route to different concrete models, and the dated-suffix tolerance in models_equivalent is exactly what keeps that from being reported.
- The Fable-tier refusal holds only for readers of the README. Whether a soft warning on unrecognized model ids is worth maintaining a recognized-id list inside vendored code is an open call.
- Tutorial repair calls route to the full-strength tutorial model. A cheaper model might be adequate for repairing a failing command when the failure output is supplied, but nobody has tested whether repair quality survives the downgrade.

## Related

- [how-to/route-modes-to-different-models](../how-to/route-modes-to-different-models.md)
- [how-to/control-spend-with-a-budget](../how-to/control-spend-with-a-budget.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [explanation/reproducibility-and-bare-mode](../explanation/reproducibility-and-bare-mode.md)
- [explanation/audit-versus-check](../explanation/audit-versus-check.md)
- [explanation/the-diataxis-mode-contract](../explanation/the-diataxis-mode-contract.md)
- [how-to/run-a-large-generation-concurrently](../how-to/run-a-large-generation-concurrently.md)
- [how-to/diagnose-environment-and-authentication-failures](../how-to/diagnose-environment-and-authentication-failures.md)

