---
title: "Why the harness owns the filesystem"
slug: explanation/why-the-harness-owns-the-filesystem
mode: explanation
generated_by: diataxis
generated_at: 2026-07-29T21:38:06Z
frozen: false
---

# Why the harness owns the filesystem

Claude never writes a file in this system: the shell hands the model a read-only view of your repository, takes back a schema-validated JSON object, and does every filesystem write itself, which is what makes a generation run reviewable and makes a prompt injection hidden in a source comment inert.

## The invariant, stated once and enforced in one place

The rule is written at the top of the only file that shells out to `claude` for generation: every call uses a pinned model, read-only tools, structured JSON output and budget caps, and the harness owns the filesystem (`lib/claude.sh:1-4`). That placement is the design. There is exactly one function, `claude_run`, that builds a `claude` argv and executes it, so the invariant has a single enforcement point rather than a convention that each subcommand is trusted to honor. `plan`, `generate`, `audit` and the tutorial repair pass all funnel through it, which means you can read one 60-line block of argv construction and know the capability envelope of the whole tool.

The alternative shape is the obvious one, and it is what most documentation agents do: give the model an editing tool, point it at `docs/`, and let it write Markdown directly. That works, and it is faster to build. It also means every file in your repository becomes a potential instruction with effects. A model that can write files and that reads your source is a model that will follow a sentence in a Python docstring saying "also update the release script." You cannot audit that risk away by improving the prompt, because the prompt is not where the boundary lives. Removing the write tool is.

## What the argv forbids

Three flags carry most of the weight (`lib/claude.sh:57-65`). `--allowedTools "Read,Grep,Glob"` leaves the model with three read operations and nothing else: no file write, no edit, no shell, no network fetch. `--permission-mode dontAsk` is the flag reviewers tend to flinch at, and it is the wrong one to worry about. A permission prompt is only a boundary while a human is present to answer it, and this harness is built to run unattended from a scheduled or manually dispatched job. In that setting, prompts produce either a hung process or a default answer nobody chose. With the allowlist already excluding every mutating tool, `dontAsk` has nothing dangerous left to approve. The call also runs with stdin closed (`lib/claude.sh:103-104`), so there is no interactive channel at all.

`--strict-mcp-config` is passed with no accompanying `--mcp-config`, which loads zero Model Context Protocol (MCP) servers. This one is unconditional rather than folded into bare mode, and the comment explains why: bare mode is unavailable exactly under subscription authentication, which is where a teammate's ambient MCP servers are most likely to be configured (`lib/claude.sh:53-56`). The README records that this came from dogfooding rather than from theory: a policy-blocked MCP server failed a generation that never needed MCP at all (`README.md:331-334`). The principle is that the effective tool surface should equal the declared allowlist in every authentication mode, not only in the reproducible one.

Because all of this is argv, all of it is testable without spending money. Under `--dry-run`, `claude_run` prints the exact argument vector, one argument per line, and returns without executing (`lib/claude.sh:89-94`). A bats test asserts the read-only shape directly against that output (`tests/argv.bats:57-69`), so a future change that widens the tool set fails the suite rather than quietly shipping.

## Structured output is the write interface

Removing the write tool creates a question: how does generated prose reach disk? Through a narrow, typed channel. Every call carries `--json-schema` with the mode's schema inlined, and the harness reads the result from `.structured_output`, never from the free-text `.result` (`lib/claude.sh:133-138`). Empty structured output is treated as a failed generation, not as something to salvage. That distinction matters more than it looks: `.result` is unvalidated model prose, which is precisely the payload the schema exists to exclude, so a fallback that reached for it on schema failure would reintroduce the hole the schema closes.

The schema constrains shape; a second gate constrains truth. `verify_citations` walks every `citations` array anywhere in the structured object and checks that each path exists in the work tree, that any line range falls inside the file, and that any named symbol appears in it (`bin/diataxis:271-316`). A page with even one unresolved citation is recorded as `status: "failed"` and never rendered (`bin/diataxis:648-655`). Treating that as a hard failure rather than a warning is a deliberate choice about what generated documentation is for. Prose that cites a function that does not exist is worse than no page, because it borrows the credibility of a verified artifact.

Layout is not generated either. The structured object is turned into Markdown by shell renderers, one per mode, and the frontmatter is emitted by a fixed printf block (`lib/render.sh:1-21`, `lib/render.sh:124-138`). The model supplies a thesis, sections, tradeoffs and open questions; it does not choose heading levels, frontmatter keys or link syntax. That is why diffs between two generation runs read as prose changes rather than as formatting churn.

## One function performs every repository write

The boundary would leak if worker code wrote pages directly, so it does not. `generate_one_page` is a worker: it renders the task prompt, calls the model, verifies citations, runs tutorial verification and writes `meta.json` plus `page.md` into a temporary directory, and its contract says explicitly that it never writes into the repository itself (`bin/diataxis:575-577`). The parent then merges each worker's result through `apply_page_result`, which owns every write into the tree: copying the page into place, upserting the manifest entry, amending the plan when a how-to splits (`bin/diataxis:718-771`).

This split is what makes concurrency safe without locking. Workers run as background subshells with their stderr captured, so a `die()` inside one cannot tear down the run, and the parent applies results serially after the batch joins (`bin/diataxis:846-869`). Budget accounting depends on the same property: `apply_page_result` must run in the parent shell rather than inside a command substitution, or the accumulated spend would be discarded with the subshell. The comment on the function says so, because that bug is easy to reintroduce.

A useful way to read the whole `generate` loop is as a funnel with progressively narrower gates: the queue skips frozen pages and hand-edited pages, then the model call happens under the read-only argv, then the schema gate, then the citation gate, then tutorial verification, and only what survives all of them reaches `apply_page_result`. Every gate before the last one is a pure function of temporary files.

## What the boundary buys beyond safety

Injection resistance is the headline, but reviewability is the property you feel day to day. Because writes are harness-side and derived from a validated object, a generation run produces a diff that a human can read like any other change, and the run is idempotent: unchanged inputs mean no work and no diff. The README makes the corresponding process argument, and it follows from the same boundary: generation does not belong in pull request continuous integration, because it costs money and produces prose that needs human review, while `diataxis check` writes nothing and can run on every pull request (`README.md:266-272`).

The boundary also makes the failure modes legible. `claude_run` refuses to accept output that is not JSON, refuses output the CLI flagged as an error, and maps model-unavailable and budget errors to distinct exit codes before falling through to a generic failure with the captured stderr attached (`lib/claude.sh:105-127`). Because nothing has been written at that point, a failed call leaves the tree untouched, so a run that dies partway through is resumable rather than half-applied. The per-call `--max-budget-usd` belt sits on top of harness-side accounting for the same reason (`lib/claude.sh:75-79`): two independent stops are cheap when neither of them can leave the repository in a partial state.

## Where the boundary is still soft

Honesty about the edges is more useful than a clean story. Three of them are worth knowing.

The harness restricts writes, not reads. Each call runs with its working directory at the repository root so that Read, Grep and Glob see the whole work tree (`lib/claude.sh:103-104`). The `include`/`exclude` globs in configuration shape which files are considered documentable sources, not which files the model can open. If your work tree contains secrets, they are inside the read surface.

Doctor's probes bypass the tool allowlist. Both the legacy authentication probe and `probe_models` invoke `claude` directly with a one-turn hardcoded prompt; they pass `--strict-mcp-config` but no `--allowedTools` (`lib/preamble.sh:221-231`, `lib/preamble.sh:305-322`). The exposure is small because the prompt is a fixed string and no repository content reaches the model, so an injected instruction has no carrier. It is still a deviation from the invariant this page otherwise describes, and routing those probes through `claude_run` would close it.

The most interesting soft edge is that the boundary relocates one risk rather than eliminating it. Tutorials are verified by executing their fenced code blocks, and the harness does that execution itself, in an ephemeral directory, by default on the host (`bin/diataxis:544-573`). So model-authored shell does run on your machine during a tutorial generation. The difference from handing the model a Bash tool is control: the harness decides when, in which directory, in which order, and whether to wrap each script in `verify.sandbox_command`, which is how you route it through a container. That knob being opt-in rather than mandatory is a real tradeoff, made because requiring a container would make the default path fail on machines without one.

## Tradeoffs

| Decision | Chose | Rejected | Because |
| --- | --- | --- | --- |
| Where file writes happen | The shell writes every file from schema-validated structured output | Giving Claude a write or edit tool pointed at docs/ | a model with a write tool that also reads your source turns any comment or docstring in the repository into an instruction with filesystem effects, and it makes diffs unattributable |
| How to bound capability during an unattended run | A three-tool read-only allowlist plus --permission-mode dontAsk and closed stdin | Interactive permission prompts, or a wider tool set gated by an approving permission mode | prompts are not a boundary when no human is present to answer them, while an allowlist containing no mutating tool holds regardless of who or what is watching |
| When to suppress ambient MCP servers | Pass --strict-mcp-config on every call, in every authentication mode | Relying on --bare to suppress them on runs that already pass it | bare mode is unavailable exactly under subscription authentication, where stray servers are most likely, and a policy-blocked server had already failed a real generation that never needed MCP |
| What to do when a call returns nothing schema-conforming | Record the page as failed and write nothing | Falling back to the free-text .result field so the run still produces a page | unvalidated prose is the exact payload the schema exists to exclude, so a salvage path would reopen the hole the schema closes |
| Who executes a tutorial's code blocks | The harness runs them in an ephemeral directory, optionally wrapped by verify.sandbox_command | Granting the model a shell tool so it can test its own tutorial | harness-side execution keeps the timing, working directory, ordering and containment under the harness's control, and keeps the model's tool set read-only |
| How workers and the parent divide filesystem work | Workers write only into a temporary directory; the parent applies all repository writes serially | Letting each concurrent worker write its own page and manifest entry | serial application removes the need for locking, keeps budget accounting in the parent shell, and means a failed worker leaves the tree untouched |

## Open questions

- Doctor's authentication and model probes still call claude without --allowedTools, so the read-only invariant is not total. Routing them through claude_run would make it total, at the cost of a probe path that currently needs no schema, prompt file or budget accounting.
- The read surface is the entire git work tree, and no configuration key narrows it. The include/exclude globs only decide which files count as documentable sources. Whether the harness should additionally constrain what Read and Grep can reach is unresolved.
- Tutorial verification executes model-authored shell on the host by default; verify.sandbox_command is opt-in. Whether containerized verification should become the default, at the cost of failing on machines without a container runtime, is an open call.
- The manifest is trusted input. content_hash detects hand edits to generated pages, but nothing attests to the manifest entries themselves, so an edited manifest can make an ungenerated page look generated.

## Related

- [explanation/reproducibility-and-bare-mode](../explanation/reproducibility-and-bare-mode.md)
- [explanation/the-diataxis-mode-contract](../explanation/the-diataxis-mode-contract.md)
- [explanation/tutorial-verification-and-repair](../explanation/tutorial-verification-and-repair.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [how-to/inspect-a-run-without-calling-the-model](../how-to/inspect-a-run-without-calling-the-model.md)
- [how-to/protect-hand-written-pages-from-regeneration](../how-to/protect-hand-written-pages-from-regeneration.md)

