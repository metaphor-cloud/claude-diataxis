---
title: "Why POSIX shell and jq"
slug: explanation/why-posix-shell-and-jq
mode: explanation
generated_by: diataxis
generated_at: 2026-07-29T21:21:49Z
frozen: false
---

# Why POSIX shell and jq

The harness is written in Bash 3.2 compatible POSIX (Portable Operating System Interface) shell with jq as its only parser so that a copy of it can be committed into any repository and run there without installing a language runtime; every anti-goal in the project, from "no site generator" to "no plugin system," exists to protect that one property.

## The constraint that produced the design

Start from the distribution model, because the language choice is downstream of it. Vendoring is the primary path: `install.sh` copies five directories (`bin`, `lib`, `prompts`, `schemas`, `share`) into `<target>/diataxis` and tells you to commit them, and git subtree and submodules are supported for the same reason (README.md:22-34, install.sh:44-49). The harness therefore lives inside somebody else's repository, on somebody else's continuous integration (CI) runner, next to somebody else's build.

That placement rules out a runtime of its own. If the harness were Python, the vendored copy would need a virtual environment, a lockfile, and an answer for what happens when the host repository pins a different interpreter. If it were Node.js, it would add a `node_modules` tree and a second `package.json` to a Rust or Go repository that has no business owning one. If it were a compiled binary, you could not read the vendored copy in a code review, and you would need per-platform release artifacts before anyone could use it.

Shell dodges all of that because the interpreter is already present wherever the work happens. `bin/diataxis` resolves its own root by walking symlinks and then sources the library files relative to it, so a vendored copy at any depth works with no install step and no environment variable (bin/diataxis:8-24). The README states the deal in three lines near the top: POSIX shell, Bash 3.2 compatible; runtime dependencies are `claude`, `jq` 1.6 or newer, `git`, and coreutils; nothing else (README.md:9-11).

Notice what the repository does not contain: there is no dependency manifest. No `package.json`, no `Cargo.toml`, no `pyproject.toml` at the root; the only ones present belong to the language fixtures under `tests/fixtures/`. The dependency list is enforced at runtime instead, by the doctor checks that refuse to proceed on a missing or old `jq` and an old `claude`, each with its own exit code (lib/preamble.sh:170-181).

## What jq buys, and what it costs

Configuration is JavaScript Object Notation (JSON), and jq is the only thing that reads it. That is a deliberate narrowing rather than an accident of convenience: one parser means one failure mode, one version floor, and one syntax to review. `config_load` reads the file with `jq -c`, deep-merges the user's keys over the defaults with jq's `*` operator, and every subsequent read goes through the two-line `cfg` accessor (lib/config.sh:118-170).

The most opinionated consequence is validation. Rather than depend on a JSON Schema library, `config_validate_jq` is a JSON Schema validator written in jq: about fifty lines implementing `$ref` resolution against `definitions`, `type` (including the integer case), `enum`, `required`, `properties`, `additionalProperties: false`, and `items`, emitting one violation per line as a JSON pointer plus a message (lib/config.sh:43-101). That is why an invalid config fails with the offending pointer and exit code 2 instead of a stack trace.

The cost is honest and worth stating: this is a subset validator. Schema keywords it does not implement are not rejected, they are ignored. A future `schemas/config.json` that reaches for `oneOf`, `pattern`, or numeric bounds would validate as though those constraints were absent. The project accepts that because the config surface is small and the schema is written by the same people who wrote the validator, but it is a place where the no-second-dependency rule buys silence rather than safety.

jq also carries the load everywhere JSON crosses a boundary. The model's structured output is read from `.structured_output` by `claude_structured` and never text-parsed (lib/claude.sh:131-133). The plan amendment for a how-to that reports two goals is a jq expression that rewrites `.pages` in place. `manifest_upsert_page` replaces or appends an entry and re-sorts by slug (lib/manifest.sh:30-36). Treating jq as the data layer rather than as a pretty-printer is what keeps the shell code from doing string surgery on JSON.

## Bash 3.2 is macOS, and it costs you arrays

The Bash 3.2 floor is a portability target, not nostalgia: macOS still ships bash 3.2, so anything newer would make the harness a Linux tool that mostly works on a developer laptop. Every file carries a `# shellcheck shell=sh` directive and the suite is checked with `shellcheck -s sh`, which enforces the constraint mechanically rather than by discipline.

Read the code and you can see the shape of what that costs. There are no arrays, so argument vectors are built by reassigning the positional parameters: `claude_run` starts with `set -- -p --model ...` and appends flags conditionally, prepending `--bare` at the front when bare mode applies (lib/claude.sh:52-82). `probe_models` does the same thing for its cheap per-model probe. There is no floating-point arithmetic in the shell, so budget math goes through three awk one-liners, `awk_float_add`, `awk_float_sub`, and `awk_float_lt`, and version comparison goes through `version_ge`, which splits on dots inside awk (lib/preamble.sh:62-129). There is no built-in templating, so `render_template` is an awk reimplementation of the `${VAR}` form of envsubst, single pass, values not re-expanded. There is no portable hashing command, so `sha256_stream` picks between GNU `sha256sum` and BSD `shasum` once, and `b64_decode` probes whether the local `base64` wants `-d` or `-D` and caches the answer in the environment.

Glob matching is the same story at a slightly higher altitude. Config `include`/`exclude` patterns are matched by rewriting `**` to `*` and running the result through a `case` statement, with a second attempt that strips a leading `*/` so a `**/foo` pattern also matches zero directories deep; `path_included` runs its body in a subshell with `set -f` so the patterns cannot expand against the current directory and the option cannot leak (bin/diataxis:155-194). A real glob library would be more precise. A `case` statement needs no library.

The fair criticism of all this is that the harness is not a shell program with a few awk helpers; it is a shell program and a substantial awk program sharing a repository. The shell adapter's `adapter_symbol_inventory` is about forty-five lines of awk that emits newline-delimited JSON by hand, with its own `jesc` escaping function, because there is no native symbol extractor for shell to call (lib/adapters/shell.sh:59-108). Counting awk as "already installed" is true, and calling the result single-language is a stretch. The defense is that awk is subject to the same test suite and the same review as everything else, and adds nothing to install.

## The alternatives, and why they lost

Python is the obvious contender and loses on the same ground it usually wins on. The harness has to document Rust, Go, Python, and TypeScript repositories, and the Python adapter already deals with `griffe` when it is present and falls back to a bundled `ast` script when it is not (README.md:240-247). A Python harness would turn that optional, per-workspace dependency into a mandatory one for every repository, including the Rust and Go ones, and would inherit the interpreter-version and environment-manager questions of whatever project it was vendored into.

Node.js has a real argument in its favor: the `claude` command-line interface (CLI) is distributed through npm, so a working install implies a working Node.js. The counterargument is that Node.js is present for the CLI, not for the harness, and depending on it would couple the harness's runtime to the CLI's packaging decision. A single compiled binary in Go or Rust would remove the runtime question entirely, at the cost of release engineering per platform and, more importantly, at the cost of vendorability: you cannot review a binary in a pull request, and "commit this directory" stops being a credible install story.

There is also a smaller, less obvious win. Because the harness is shell, its own dogfooding case is not special. A fifth adapter, `shell`, was added beyond the four in the original specification precisely so the harness could document repositories like itself, and it detects last because most repositories contain some shell (README.md:327-330, lib/adapters/shell.sh:1-24).

## The anti-goals are the same decision

The anti-goal list reads as a set of separate refusals: no static site generator, no theme, no search index, no web user interface, no plugin system, no language runtime dependency (README.md:336-340). It is really one refusal applied five times.

A site generator is a runtime dependency wearing a different hat, and it is an ecosystem-specific one: MkDocs pulls Python, Docusaurus pulls Node.js, mdBook pulls Rust. Choosing any of them would make the harness partisan about the host repository's toolchain, which is exactly what the shell choice was protecting against. So the output contract stops at plain Markdown with YAML (YAML Ain't Markup Language) frontmatter, which all four of those tools consume, and the question of how documentation is published is left to the repository that owns it. A theme and a search index are downstream of a generator and disappear with it.

A plugin system fails for a second reason on top of the first. In a shell program, "plugin" means sourcing a file the harness did not write, which means executing arbitrary code with the harness's own privileges in the middle of a run. The extension point is instead a closed set: `detect_adapter` iterates a fixed list of five names and sources `lib/adapters/<name>.sh` (bin/diataxis:199-208), and each adapter implements exactly four functions. That closure is also what makes the one documented shellcheck suppression defensible; `.shellcheckrc` disables SC1090 for the variable-path source, and the justification written in the file is that the adapter set is closed and each file is checked individually (.shellcheckrc:1-4). Writing a new adapter is a change to the harness, reviewed like any other change, rather than a runtime injection point.

## What the constraint buys back

Choosing shell to avoid dependencies also happens to produce a program that is unusually easy to inspect, and the project leans on that hard.

The test story needs almost nothing. The harness's own CI installs shellcheck in one job and `bats` plus `jq` in the other, and that is the entire toolchain (.github/workflows/ci.yml:19-31). The bats suite stubs `claude` as a PATH shim, so no test makes a live call and no test needs credentials.

The seam that makes model behavior testable exists because of the language, not in spite of it. Since argv is assembled in the positional parameters, `--dry-run` can print it verbatim: first line `claude`, one argument per line, terminated by a blank line (lib/claude.sh:84-89, README.md:63-65). Every test that touches model selection asserts against that output, which means routing, effort, fallback, bare mode, and the per-call budget cap are all verified without spending a cent. A program that built its request inside an HTTP client library would have had to invent that seam.

The same transparency applies to state. `compute_inputs_hash` concatenates labeled lines (source file digests in sorted order, then the system prompt, task template, schema, model block, and plan entry) and hashes the stream (lib/manifest.sh:63-81). You can read that function and know exactly what makes a page stale, which is a different kind of confidence from reading a serialization library's documentation.

## Open questions

The Bash 3.2 floor is justified by macOS shipping bash 3.2, but the harness is checked as `sh`, not as bash, and it runs under `/bin/sh` (which is dash on Debian-family systems). It is worth asking whether "Bash 3.2 compatible" is still describing a real constraint or has become shorthand for "POSIX discipline, enforced by shellcheck." Nothing in the code depends on bash specifically, so the honest version of the rule may be narrower than the stated one.

The jq subset validator will eventually be asked to check a schema keyword it does not implement, and its current failure mode is silence. A cheap mitigation would be for the validator to reject schemas containing keywords it cannot enforce, so the gap becomes an error rather than a false pass. That has not been done.

The hand-rolled JSON emission in awk is the least defensible part of the no-dependencies position. `jesc` escapes backslashes, quotes, tabs, and strips carriage returns, which covers the cases that occur in shell source, but it is not a general JSON string encoder; a control character in a doc comment would produce output jq rejects. Routing adapter output through jq for encoding would fix it at the cost of a process per record.

Concurrency is the place where the absence of a real runtime shows most. Because shell has no job pool, `--concurrency` is implemented as fixed-size batches with a `wait` barrier between them, capped at 4, and workers write only into a temporary directory so the parent can apply all repository writes serially (README.md:319-321). That is correct and simple, and it leaves the slowest page in each batch dictating the batch's wall time. Whether that matters enough to justify a more complicated scheduler in shell is unresolved.

## Tradeoffs

| Decision | Chose | Rejected | Because |
| --- | --- | --- | --- |
| Implementation language | POSIX shell, checked as `sh`, Bash 3.2 compatible, with awk for arithmetic, templating and text extraction | Python, Node.js, or a compiled Go or Rust binary | The harness is vendored into other people's repositories, so a runtime of its own would impose an environment manager on a Rust or Go project, and a binary could not be reviewed in a pull request or copied in as source |
| Configuration parsing and validation | JSON config with jq as the only parser, including a JSON Schema validator written in jq | A real JSON Schema library, or a second config format such as YAML or TOML | jq is already a hard dependency and a second one is not acceptable; the cost is a subset validator that ignores keywords it does not implement rather than rejecting them |
| Floating-point arithmetic, version comparison and templating | Small awk helpers (`awk_float_add`, `version_ge`, `render_template`) | bash arithmetic (no floats), `bc` (not universally installed on minimal images), or a scripting language | awk is present wherever the harness runs and is already needed by the adapters, so these helpers add no install surface |
| Extensibility model | A closed set of five adapters, each implementing exactly four functions, sourced from a fixed name list | A plugin system that discovers and sources user-supplied files | Sourcing files the harness did not write means executing arbitrary code with the harness's privileges mid-run, and the closed set is also what makes the single SC1090 suppression defensible |
| Output format and publishing | Plain Markdown with YAML frontmatter, and no opinion about how it is rendered | A bundled static site generator, theme, search index, or web user interface | Every generator is ecosystem-specific (MkDocs implies Python, Docusaurus implies Node.js, mdBook implies Rust), so bundling one would reintroduce exactly the runtime dependency the language choice was avoiding |
| Concurrency implementation | Fixed-size batches with a `wait` barrier, capped at 4, workers writing only to a temporary directory | A worker pool with per-slot refill, or parallel writes into the repository | Shell has no job pool primitive, and serializing all repository and manifest writes in the parent keeps runs idempotent; the price is that the slowest page in a batch sets the batch's wall time |

## Open questions

- Is "Bash 3.2 compatible" still a real constraint? The code is checked as `sh` and runs under `/bin/sh`, and nothing appears to depend on bash specifically, so the accurate rule may be narrower than the stated one.
- Should `config_validate_jq` reject schemas that use keywords it cannot enforce (such as `oneOf`, `pattern`, or numeric bounds) instead of silently ignoring them and reporting a false pass?
- The hand-rolled `jesc` escaping in the shell adapter's awk program covers the cases that occur in shell source but is not a general JSON string encoder; a control character in a doc comment would produce output jq rejects. Is a process-per-record trip through jq worth the correctness?
- Does the batch-with-barrier concurrency model cost enough wall time on large plans to justify a more complicated scheduler written in shell?
- Is jq 1.6 the right version floor now, or does the validator rely on behavior that would let the floor move up or down?

## Related

- [explanation/why-the-harness-owns-the-filesystem](../explanation/why-the-harness-owns-the-filesystem.md)
- [explanation/language-adapter-architecture](../explanation/language-adapter-architecture.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [explanation/reproducibility-and-bare-mode](../explanation/reproducibility-and-bare-mode.md)
- [how-to/vendor-the-harness-into-a-repository](../how-to/vendor-the-harness-into-a-repository.md)
- [how-to/run-the-harness-test-suite](../how-to/run-the-harness-test-suite.md)

