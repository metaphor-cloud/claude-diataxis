---
title: "Tutorial verification and repair"
slug: explanation/tutorial-verification-and-repair
mode: explanation
generated_by: diataxis
generated_at: 2026-07-29T21:16:05Z
frozen: false
---

# Tutorial verification and repair

Tutorials are the only Diataxis mode whose central promise is mechanically falsifiable, so the harness executes their code before publishing them, feeds any failure back into a bounded repair loop, and records the outcome as a `verified` boolean that CI can gate on rather than as a quality score a human has to interpret.

## Why only tutorials get executed

A tutorial makes a promise about the future: follow these commands in this order and you will end up here. That promise is a claim about the behavior of a program, and a claim about the behavior of a program can be tested by running it. The other three modes make different kinds of claims. Reference material asserts that a signature and a description match the source, which the harness checks by resolving citations rather than by running anything. Explanation asserts that a design decision had a reason, which no interpreter can adjudicate. A how-to asserts that a sequence of steps achieves one goal, which is closer to a tutorial, but a how-to runs against a reader's existing system, with their credentials and their data, so there is no fresh empty directory in which its steps are meant to succeed.

So the harness draws the executable boundary at exactly one mode. `generate_one_page` gates the whole verification path on `[ "$_mode" = "tutorial" ]` (`bin/diataxis:659`), and `render_frontmatter` only emits a `verified` key when the caller passes one, which for the other three modes it never does (`lib/render.sh:16`). Code blocks in how-to guides are still policed, but by judgment rather than by execution: the `unverified_code` audit rule asks a model whether a fenced block states an expected result, and the audit prompt is handed the configured executable languages so it knows which blocks that rule is about (`bin/diataxis:1013`). That is a different instrument for a different claim, and it lives in `audit`, not in `generate`.

## The model cannot run its own code, by design

Every generation call is read-only. `claude_run` pins `--allowedTools "Read,Grep,Glob"` and loads zero Model Context Protocol (MCP) servers, and the file header states the rule plainly: the harness owns the filesystem and Claude never writes files (`lib/claude.sh:1-5`, `lib/claude.sh:52-57`). That constraint is what makes verification a harness responsibility rather than something you could delegate to the model with an instruction like "test your tutorial before returning it".

The consequence is worth stating because it shapes everything downstream. The model that writes the tutorial has never seen it run. It has read your source files and produced a structured object; whether that object's commands work is an empirical question the shell answers afterwards. Verification is therefore not the model checking itself, which would be circular, but an independent execution whose failure output becomes new input. The tutorial task prompt is explicit with the model about this division of labor: the harness will execute every bash, sh and console block in order in a fresh empty directory, and they must all succeed (`prompts/task/tutorial.tmpl:14`).

## Block extraction works because the tutorial is data first

The harness never parses Markdown to find code. It cannot, because at verification time the Markdown does not exist yet: rendering happens after verification, with the `verified` flag as an argument (`bin/diataxis:690-691`). What exists is the structured object the model returned, whose `steps` array carries `code`, `language`, `expected_output` and `checkpoint` as separate typed fields (`schemas/tutorial.json:29-55`).

`tutorial_extract_blocks` reads that array with jq, keeps the steps whose `language` appears in `verify.executable_languages`, and writes one `step-N.sh` per surviving block, where N is the step's index in the array (`bin/diataxis:519-539`). Three details in that function are load-bearing. It base64-encodes each field before pushing it through the shell pipeline and decodes on the other side, so a tutorial containing tabs, newlines or quotes in its code cannot corrupt the loop that consumes it. It deletes any `step-*.sh` from a previous attempt first, so a repair that removes a step does not leave the old script behind to be executed anyway. And for `console` blocks it keeps only lines beginning with `$ `, on the convention that a console transcript interleaves commands with their output, so everything else in that block is output to display rather than a command to run.

That last rule is why `console` is in the default executable set alongside `bash` and `sh` (`lib/config.sh:32`). Blocks in any other language are silently not executed, which means a Rust or Python tutorial gets a `verified: true` page on the strength of running whatever shell scaffolding surrounds its untested source. Adding `python` to `executable_languages` makes those blocks run, at which point the interpreter has to exist on whatever machine performs verification.

## The empty directory is part of the specification

`tutorial_verify` creates `run/` under the page's temporary output directory, wipes it first, and executes each step script from inside it with `sh -e`, in numeric step order so that step 10 follows step 9 rather than step 1 (`bin/diataxis:545-563`). Nothing else is in that directory. The repository is not the working directory; no fixture is seeded; no state survives from a previous attempt.

This is the strictest interpretation of what a tutorial is, and it is a deliberate one. A newcomer following your tutorial starts from nothing, so the verification environment starts from nothing too. The effect on the prose is real and mostly good: a tutorial cannot get away with "now run the build" without having first said how to obtain the thing being built. The cost is equally real. A tutorial that legitimately needs a cloned repository, a network service or a compiler toolchain has to establish all of that in its own early steps, or fail. `verify.sandbox_command` is the pressure valve: set it and each step script is passed as an argument to your wrapper instead of run directly, which is how you point verification at a container image that already has the toolchain installed (`bin/diataxis:559-560`, `README.md:229-231`).

When a step exits non-zero, the function prints a three-part report and returns immediately: which step script failed and with what status, the full text of that script, and the last 40 lines of its combined output (`bin/diataxis:564-571`). Returning on the first failure rather than continuing is the right call for repair, because in a sequential tutorial every step after a broken one is executing against a world that never arrived. It does mean each attempt reveals exactly one failure, so a tutorial with two independent mistakes needs two repair rounds to surface both.

## Repair is a loop with a hard ceiling

The repair loop is about a dozen lines and does one thing: it appends the failure report to the original task prompt, adds an instruction to make every step run successfully in a fresh empty directory and return the full corrected tutorial, and calls the model again (`bin/diataxis:664-682`). The regeneration is not a patch. The model returns a complete replacement tutorial, which is then re-extracted and re-executed from scratch. That whole-object regeneration is what keeps the loop simple: there is no diff to apply, no partial state to reconcile, and the schema constraint is identical on every attempt.

The repair call uses the same model routing as the initial tutorial call but half the turn allowance, 12 against 24, on the reasoning that repair starts from a written tutorial and a concrete error rather than from a blank page (`bin/diataxis:675`, `bin/diataxis:618`). Its cost is accumulated into the page's total rather than discarded, so `diataxis cost` and the run budget both see what repair actually spent (`bin/diataxis:676`).

The ceiling is `verify.max_repairs`, default 2 (`lib/config.sh:31`). A bound matters here more than in most loops, because this particular loop is a plausible money pump: tutorial pages route to Opus at high effort, and a tutorial that fails for an environmental reason will fail identically forever while spending an Opus call per round. Two attempts is a judgment that a tutorial failing three executions in a row usually has a wrong premise rather than a typo, and a wrong premise is a thing for a human to look at. One rough edge lives in the loop's structure: if a repair call comes back with no schema-conforming output, `_structured` and therefore `_failures` are left unchanged, so the attempt is consumed without producing new information (`bin/diataxis:677-681`).

## What verified: false means downstream

When the loop exits with failures still in hand, the page is written anyway. `_verified` is set to `false`, `render_page` stamps `verified: false` into the frontmatter, and the manifest entry records the same boolean (`bin/diataxis:683-687`, `lib/render.sh:16-18`, `bin/diataxis:712`). Generation reports success. This is the part that surprises people, and it is the most considered decision in the whole path.

Publishing a failed tutorial is defensible because a tutorial is not only its commands. The structure, the prose, the citations and the ordering may all be sound while one command is wrong, and a page you can read and fix is worth more to a reviewer than a generation failure and no artifact. It is also defensible because the failure is not lost: it is recorded as a machine-readable claim in two places, so nothing depends on anyone remembering it.

`cmd_check` is where that claim acquires teeth. When `verify.required` is true, check walks the tutorial slugs in the plan, looks up each one's manifest entry, counts the entries whose `verified` is exactly `false`, and exits 32 if the count is non-zero (`bin/diataxis:1084-1096`, `bin/diataxis:1117-1119`, `lib/preamble.sh:22`). Two properties of that walk are worth internalizing. The comparison is an explicit equality test against `false` rather than a truthiness check, because jq's `//` operator treats `false` as empty and would silently pass every failed tutorial, a subtlety the code comments on directly. And the walk starts from the plan and requires a manifest entry, so a planned tutorial that was never generated does not count as unverified. It surfaces as stale instead, and exits 31.

Two escape hatches exist, at different altitudes. Setting `verify.required` to false leaves verification running and the frontmatter honest but stops check from failing on it, which is the right setting for a repository that wants the signal without the gate. Setting `verify.mode` to `off` skips execution entirely (`schemas/config.json:46`), which leaves `_verified` empty, omits the `verified` key from the frontmatter, and writes `null` to the manifest, so nothing downstream can distinguish those tutorials from non-tutorial pages.

## What verification does not tell you

The check is exit statuses, and only exit statuses. `expected_output` is rendered into the page under a "You should see" heading (`lib/render.sh:96-98`) and is never compared against what the command actually printed. A tutorial can therefore be `verified: true` while promising output that no longer resembles reality, which is precisely the failure mode readers notice first. Comparing them would need normalization of timestamps, paths, versions and ordering, and a false failure on every cosmetic output change would make the gate untrustworthy in a different way, so the harness settles for the weaker claim it can make reliably.

`verified: true` is also a point-in-time fact, not a standing one. It is written once, alongside the `inputs_hash` that governs regeneration, and nothing re-executes a verified tutorial afterwards. If the tool your tutorial drives changes behavior without any of that tutorial's cited source files changing, the hash does not move, the page is not stale, and the stale `verified: true` stands. Verification is bolted to the generation pipeline rather than to a test runner, which is the price of a harness that costs nothing to keep installed.

Finally, the default is host execution. Absent `verify.sandbox_command`, model-generated shell runs on the machine invoking `diataxis generate`, in an empty directory but with your user's full authority. The empty directory limits accidents, not intent. If you generate documentation for code you did not write, or in continuous integration with credentials in the environment, the container wrapper is the configuration that makes that safe.

## Tradeoffs

| Decision | Chose | Rejected | Because |
| --- | --- | --- | --- |
| How to check that tutorial code works | Execute every block and require exit status zero | Compare actual output against the tutorial's stated expected_output | Output comparison needs normalization of timestamps, paths and versions, and a gate that fails on cosmetic output changes stops being trusted |
| How long to keep repairing a failing tutorial | A hard ceiling of verify.max_repairs, default 2 | Iterate until the tutorial passes | Tutorial pages route to Opus at high effort, so an environmentally impossible tutorial would spend without bound; three failures in a row usually means a wrong premise, which is human work |
| What to do when repairs are exhausted | Write the page with verified: false and let check exit 32 | Fail the generation and produce no page | A readable page plus a machine-readable false claim is more useful to a reviewer than nothing, and the gate still refuses to let it merge |
| Where tutorial code executes | A wiped empty directory, with verify.sandbox_command as the opt-in container hook | The repository working tree | A newcomer starts from nothing, so a tutorial that assumes a prepared workspace should fail; the wrapper covers the cases where a toolchain genuinely has to pre-exist |
| Which fenced blocks count as executable | An allowlist in verify.executable_languages, defaulting to bash, sh and console | Attempt to run every block whose language names an interpreter | The harness has no per-language runtime dependency, so running arbitrary interpreters would import exactly the dependency the design avoids |
| Who runs the tutorial's code | The harness, after the read-only generation call returns | Grant the generation call write and execute tools so the model can test its own tutorial | The harness owns the filesystem; a model that verifies its own output is checking itself, and the failure report only carries information because an independent process produced it |

## Open questions

- Should verification diff actual output against expected_output, at least in a whitespace-insensitive or substring mode? Today a tutorial can be verified: true while promising output that no longer matches, which is the discrepancy readers hit first.

## Related

- [explanation/why-the-harness-owns-the-filesystem](../explanation/why-the-harness-owns-the-filesystem.md)
- [explanation/the-diataxis-mode-contract](../explanation/the-diataxis-mode-contract.md)
- [explanation/audit-versus-check](../explanation/audit-versus-check.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [how-to/verify-tutorial-code-in-a-container](../how-to/verify-tutorial-code-in-a-container.md)
- [how-to/gate-pull-requests-on-documentation-freshness](../how-to/gate-pull-requests-on-documentation-freshness.md)

