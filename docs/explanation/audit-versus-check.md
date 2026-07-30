---
title: "Audit versus check"
slug: explanation/audit-versus-check
mode: explanation
generated_by: diataxis
generated_at: 2026-07-29T21:09:49Z
frozen: false
---

# Audit versus check

The split between `diataxis audit` and `diataxis check` is not two views of one rule set: it is a cost and determinism boundary drawn straight through the rubric, so that the rules a shell can decide from hashes and the filesystem gate every pull request for free, while the rules that need a model to read prose cost money, run on demand, and only ever report.

## One rubric, two budgets

The seven audit rules (`mode_mixing`, `title_not_task_shaped`, `unverified_code`, `broken_citation`, `stale`, `orphan`, `missing_reference`) share a single schema enum, so a finding looks identical whichever command produced it. What differs is who can decide it.

Four of the rules are decidable by the harness alone. `stale` compares a recomputed inputs hash against the manifest entry. `broken_citation` re-runs the same citation resolver that already gates generation. `orphan` is a set difference between the files under `docs/` and the slugs in the plan. `missing_reference` is a set difference between the symbol inventory and the symbol names recorded on reference pages. None of that needs a model, and `local_findings` computes all of it with `jq`, `git ls-files` and `grep`.

The other three need someone to read the prose and form an opinion. Whether an explanation has drifted into numbered steps, whether a how-to title is task-shaped, whether a fenced block states an expected result: these are judgments about writing, not facts about the filesystem. `model_findings` renders one audit prompt per page and spends a Sonnet call on each.

That asymmetry is the whole design. It is not that the deterministic rules are more important; it is that they are free and repeatable, and free and repeatable is what a gate on every pull request has to be.

## The line is not clean, and that is deliberate

Two rules sit on both sides. `broken_citation` and `missing_reference` appear in the model's rubric and in the local pass, computed differently each time.

The local `broken_citation` check reads the citations recorded in the manifest and feeds them to `verify_citations`, the same function that refuses to write a page whose citations do not resolve. So the predicate that guards a page at write time is the predicate that re-checks it later, and the two cannot drift because there is only one implementation. The model's version is weaker and broader: it reads the rendered page, finds a path or symbol mentioned in the body, and is told to confirm it with Read, Grep or Glob before reporting. It can catch a reference the harness never recorded as a citation, which the local pass is structurally blind to.

The same holds for `missing_reference`. Locally it is inventory minus documented symbols, mechanical and complete. In the model's rubric it means a symbol used prominently in a page with no reference entry linked, which is a claim about emphasis that no hash can make.

The overlap costs a little duplicated work and buys redundancy on the two rules where a false negative is most expensive. `cmd_audit` unions both streams and dedupes with `unique`, so identical findings collapse and genuinely different ones both survive.

Note also what the two passes look at. The local rules walk the plan and the manifest. `audit_targets` walks `docs/` on disk, so the model reviews hand-written pages the plan has never heard of.

## Why audit always exits 0

`cmd_audit` prints findings and returns. There is no exit-code mapping, no threshold, no failure path. The README records this as a deliberate decision: audit is a reporting tool, and severities map to exit behavior in `check` instead.

The reasoning is about how you actually use it. Audit is the command you run while editing, on a single page, to see what the rubric thinks of your draft. A tool you invoke in a loop should not abort your shell script or your `make` chain because it found a warning; you asked it to look, and it looked. `render_audit_findings` formats the result for a human on stderr, and `--json` sends the same findings to stdout for anything that wants to parse them.

A second reason is that audit spends money. It makes one model call per page under `docs/` by default. A command with that cost profile should not be sitting in a gate where somebody wired it in because it happened to return non-zero at the right moments. Making the exit code carry no signal removes the temptation.

The consequence you have to accept: nothing about running audit is enforceable. If you run it and ignore every finding, no automation notices. That enforcement lives in exactly one place, and it is a different command.

## Why check maps severities to exit codes

`cmd_check` writes nothing and communicates entirely through its exit status, because that is the only channel a continuous integration job reliably reads.

The mapping is not a single non-zero code. Findings whose rule is not `stale` and whose severity appears in `audit.fail_on` (default `["error"]`) exit 30. Staleness exits 31. Unverified tutorials exit 32. The precedence is the order of those tests: an audit failure masks staleness, which masks an unverified tutorial, so one run reports one cause.

Separate codes exist because the three failures want different reactions. Staleness means "regenerate and commit", which is mechanical and can be automated. A rubric error means "a human wrote something that misleads", which cannot. An unverified tutorial means "the code in the docs does not run", which is a product bug wearing a documentation costume. Collapsing them into exit 1 would throw away the only distinction the caller can act on.

Two consequences of the specific filter are worth naming. `stale` is excluded from the severity test by rule name, so its own severity is irrelevant and it always routes to 31. And `broken_citation` carries severity `error`, so a purely local, model-free finding is what most often produces exit 30 in a default configuration. Meanwhile `orphan` and `missing_reference` are `warning`, so under the default `fail_on` they can never fail a gate at all: they exist as annotations, nothing more.

## Why check insists on reproducible auth

`cmd_check` calls `require_bare_capable` before it does anything else, and dies with exit 16 if the available credentials cannot support `--bare`.

This looks strange at first, because the default `check` makes no model calls. The requirement is not about this run; it is about what the command promises. A gate is only useful if its verdict is a property of the repository rather than of the machine that ran it. Bare mode is what makes that true: it skips hooks, skills, plugins, MCP servers, `CLAUDE.md` and auto memory, so a teammate's local `~/.claude` cannot change the answer. Subscription keychain auth cannot run bare, so a `check` under that auth would be a gate whose result depends on whose laptop it ran on.

Failing loudly at the start is kinder than the alternative. The alternative is a `check` that quietly runs without `--bare`, passes on your machine, and fails in the shipped GitHub Actions job, or worse, passes in both for reasons nobody can reconstruct. `audit` has no such requirement, and it should not: it is advisory, and being able to run it against your subscription login while drafting is the point.

The escape hatch is `audit.model_audit_in_check`, which opts the model rules into `check`. Turn it on and the bare requirement stops being theoretical, since now there really are model calls whose context you want pinned.

## Why generation stays out of pull request CI

The shipped workflow runs `diataxis check` and nothing else, and the comment at the top of that file says why: generation costs money and produces prose that needs human review.

Both halves matter. The cost half is arithmetic. Generation routes explanation and tutorial pages to Opus at high effort, and a full medium-repository run lands in the tens of dollars. Wire that to `on: pull_request` and every push to every branch bills you for prose nobody asked for.

The review half is the stronger argument. Generated documentation is a change to your repository's public voice. It asserts architectural claims, names tradeoffs, and tells readers what to type. Continuous integration cannot review that. It can only observe that a command exited 0, which for generation means "the model returned schema-conforming output whose citations resolved", not "this page is true and worth reading". A bot that commits documentation on green is a bot that publishes unreviewed opinions under your name.

So the intended shape is: generate from a manual or scheduled workflow, or locally; commit the diff; review it like any other change; and let `check` on every pull request keep the committed result honest. That gives you a gate that is free, fast, deterministic and writes nothing, and a generator that is expensive, occasional, and always mediated by a person. Trying to have one command do both jobs is what forces the compromise this split avoids.

## Tradeoffs

| Decision | Chose | Rejected | Because |
| --- | --- | --- | --- |
| Which rules run in `check` by default | Only the deterministic local subset computed by `local_findings` | The full rubric, including the model pass, on every run | `check` runs on every pull request; a model call per page would make the gate cost money and vary run to run, which is the opposite of what a gate is for. `audit.model_audit_in_check` remains as an opt-in. |
| `audit`'s exit code | Always 0, findings are output only | Non-zero when findings exist | Audit is a reporting tool run mid-edit and in loops, and it spends money per page; a meaningful exit code would both break that usage and invite people to wire it into a gate where its cost does not belong. |
| How `check` signals failure | Distinct codes by cause: 30 rubric, 31 stale, 32 unverified tutorial | A single non-zero exit code | Staleness is mechanically fixable by regenerating, a rubric error needs a human, and an unverified tutorial is a broken command. The exit code is the only channel a CI job reads reliably, so it should carry the distinction. |
| Auth requirements for `check` | Require bare-capable auth and die with exit 16 otherwise | Fall back to whatever credentials are available, as `generate` does with a warning | A gate whose verdict depends on the local `~/.claude` is not a gate. Failing at the start is cheaper than a result that disagrees between a laptop and CI for unreconstructable reasons. |
| Where generation runs | Manual or scheduled workflow, or locally, with the diff committed and reviewed | `diataxis generate` on pull requests | Generation bills per page at Opus rates and emits prose asserting architectural claims. CI can verify that output conformed to a schema; it cannot verify that a paragraph is true. |
| Overlap on `broken_citation` and `missing_reference` | Compute both locally and keep them in the model rubric, then union and dedupe | Assign each rule to exactly one pass | The local versions are complete over recorded citations and inventory symbols; the model version catches references in the prose that were never recorded as citations. Duplicated effort is cheap next to a missed broken link. |

## Open questions

- `--page` scoping is inconsistent across the local rules. The staleness pass requires an exact slug match, the orphan pass matches the flag as a substring of the relative path, and `missing_reference` is skipped entirely whenever `--page` is set. Whether that is deliberate narrowing (a single-page audit should not report repository-wide inventory gaps) or accumulated drift is not recorded anywhere.
- With `audit.model_audit_in_check` enabled, `check` makes one model call per page under `docs/` but does not report what the run cost, and the budget accounting that guards `generate` does not visibly apply. A large docs tree can turn the pull request gate into recurring per-page spend that nobody is watching.
- The audit schema's rule enum includes `stale` and `orphan`, but the model's rubric does not list either, so the model is technically able to emit findings for rules the local pass is meant to own. Nothing in `cmd_audit` rejects that, and a duplicate would only collapse if it matched a local finding field for field.
- Under the default `audit.fail_on` of `["error"]`, no `warning`-severity rule can ever fail `check`, which means `orphan` and `missing_reference` are permanently advisory. It is not clear whether teams are expected to widen `fail_on`, or whether those two rules should be error-severity and the default is the compromise.

## Related

- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [explanation/reproducibility-and-bare-mode](../explanation/reproducibility-and-bare-mode.md)
- [explanation/model-routing-and-cost](../explanation/model-routing-and-cost.md)
- [explanation/tutorial-verification-and-repair](../explanation/tutorial-verification-and-repair.md)
- [how-to/gate-pull-requests-on-documentation-freshness](../how-to/gate-pull-requests-on-documentation-freshness.md)
- [how-to/resolve-audit-findings](../how-to/resolve-audit-findings.md)

