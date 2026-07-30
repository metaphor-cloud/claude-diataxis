---
title: "Language adapter architecture"
slug: explanation/language-adapter-architecture
mode: explanation
generated_by: diataxis
generated_at: 2026-07-29T21:39:36Z
frozen: false
---

# Language adapter architecture

A language adapter in this harness is a sourced shell file that defines four functions, because the only thing the harness needs from a language is a list of documentable files, a list of context files, and a symbol inventory that carries its own confidence label.

## Four functions, sourced in a subshell

The whole adapter interface is four function names: `adapter_detect`, `adapter_source_globs`, `adapter_symbol_inventory`, and `adapter_context_files`. Every adapter file repeats that contract in its own header comment, and the README states it once for all five languages (README.md:235-238). There is no registration call, no capability manifest, no version negotiation, and no lifecycle hooks. An adapter is a file you source.

That choice follows from where adapters run. `run_adapter` changes directory into the workspace, sources the adapter file, and calls one function, all inside a subshell (bin/diataxis:212-215). The subshell is the isolation mechanism a plugin system would otherwise have to provide. Sourced definitions cannot leak into the harness, a stray `cd` cannot move the parent, and adapters never need teardown code because the process that held their state exits when the function returns. Nothing needs unloading because nothing was loaded.

The same subshell explains why the contract says every emitted path is workspace-relative. An adapter has no idea where it sits in a monorepo, and does not need to: `full_symbol_inventory` rewrites each record's `path` to a repository-relative one and stamps on the workspace name and the adapter that produced it (bin/diataxis:261-269). Path arithmetic lives in one place, so adapter authors write `git ls-files '*.go'` and stop thinking about it.

The README lists "no plugin system" among the harness anti-goals, next to no static site generator and no language runtime dependency (README.md:336-340). Read the adapters and the anti-goal looks less like asceticism and more like an accurate description: four function names and a subshell already do the job a plugin system would be built to do, and they add no loader, no interface version, and nothing to debug when a load fails. The cost lands in one place: shellcheck cannot follow a source through a variable path, so `SC1090` is disabled globally with the justification that the adapter set is closed and each file is linted individually (.shellcheckrc:1-4).

## Detection is a first-match ladder and shell stands at the bottom

`detect_adapter` walks `rust`, `go`, `python`, `typescript`, `shell` and returns the first adapter whose `adapter_detect` succeeds (bin/diataxis:199-208). First match wins. There is no scoring, no confidence value, and no way for two adapters to claim one directory. A workspace has exactly one language, and a repository that mixes languages splits into workspaces in configuration instead.

Order therefore carries real meaning, and the four leading adapters earn their places by testing for a build manifest. Rust checks for `Cargo.toml`, Go for `go.mod`, Python for `pyproject.toml` or `setup.py`, TypeScript for both `package.json` and `tsconfig.json` (lib/adapters/rust.sh:6, lib/adapters/go.sh:6, lib/adapters/python.sh:6, lib/adapters/typescript.sh:6). Those tests are cheap, decisive, and almost never wrong, because a build manifest is a declaration of intent by the repository's authors rather than an inference from file contents.

Shell has no such manifest, which is exactly why it detects last. Its detection asks whether any tracked `*.sh` or `*.bash` file exists, and failing that, whether any tracked file under `bin/` starts with a shell shebang (lib/adapters/shell.sh:13-24). That predicate is true of an enormous number of repositories, including most Rust, Go, Python and TypeScript ones, since almost every project carries a release script or a git hook. Put the shell adapter first and it would swallow the repository whole and produce reference pages about your continuous integration helpers instead of your library. Put it last and it claims only a workspace no other adapter recognizes, which is the intent recorded in the adapter header, in the detection comment, and in the README's list of deviations (lib/adapters/shell.sh:6-11, bin/diataxis:196-198, README.md:327-330).

The shell adapter exists at all for a self-referential reason worth stating plainly: the harness is written in POSIX shell, and without a fifth adapter it could not document itself. Dogfooding drove the addition, and the ordering rule is what makes the addition safe for everyone else.

## Every record names the strategy that produced it

The inventory format is newline-delimited JSON (NDJSON) with a fixed field set: `{name, kind, signature, path, line, visibility, doc_comment, strategy}` (README.md:236-237). Four of those fields are facts about the symbol. `strategy` is a fact about the extraction, and it is the field that makes the rest of the design work.

The values are specific about provenance rather than merely truthy. Rust emits `rustdoc-json` when it parses rustdoc's JSON index, and `grep` or `cargo-metadata+grep` when it falls back (lib/adapters/rust.sh:66, lib/adapters/rust.sh:76-80). TypeScript emits `typedoc` (lib/adapters/typescript.sh:62). Python emits `griffe`, `python-ast`, or `grep` depending on which rung it reached (lib/adapters/python.sh:85, lib/adapters/python_ast.py:68, lib/adapters/python.sh:113). Go and shell emit `go-list+grep` or `grep` (lib/adapters/go.sh:29-31, lib/adapters/shell.sh:68).

The reason for that granularity is that these strategies disagree about the world in ways that matter to a documentation writer. A rustdoc or typedoc record knows the resolved type of a return value. A grep record knows the characters that appeared on one line. Both claim to be a signature. Without a provenance label, a reference page would present them identically and a reader would have no way to tell a compiler-verified signature from a text match that happened to look like one.

What consumes the label is the honest and slightly surprising part. No harness code branches on `strategy`. The one non-adapter mention of it is a comment above `full_symbol_inventory` (bin/diataxis:260). The consumer is the model: whole inventory records reach the reference prompt verbatim, under an instruction to verify each signature against the source because the inventory may be approximate (prompts/task/reference.tmpl:7-9). The label sets a prior for how much verification a given record deserves. Compare that with `visibility`, which the deterministic `missing_reference` rule reads directly to decide whether an undocumented symbol is a finding (bin/diataxis:979-996). One field steers a model, the other steers code, and the design keeps them distinct.

## Absent native tooling degrades the inventory, never the run

Each adapter's inventory function is a ladder, tried best rung first. Rust runs `cargo +nightly rustdoc` with JSON output only when both `cargo` and a nightly toolchain answer, and drops to a grep pass over `pub` items otherwise (lib/adapters/rust.sh:28-35). TypeScript tries `typedoc --json` when `typedoc` is on the path (lib/adapters/typescript.sh:27-34). Python has three rungs: `griffe dump` when the module resolves, then the bundled `python_ast.py` under any available interpreter, then grep over `def` and `class` lines (lib/adapters/python.sh:37-55). Shell has one rung, because no native symbol tooling for shell exists to put above it (lib/adapters/shell.sh:6-11).

The important property is what happens when a rung fails, and the answer everywhere is the same: fall to the next rung and keep going. `_rust_inventory_rustdoc` removes its temporary directory and returns nonzero when the rustdoc invocation fails, when no JSON file lands, or when the `jq` transformation of the index does not fit, with a comment stating that the rustdoc JSON format is unstable so any surprise falls back to grep (lib/adapters/rust.sh:37-73). Missing native tooling never fails a run (README.md:252-253).

That is a deliberate trade of fidelity for reachability. The alternative, refusing to document a Rust crate without a nightly toolchain, would make the harness unusable in the environments where documentation generation actually happens: a stable-only continuous integration image, a container without `typedoc` installed, a contributor's laptop. The harness prefers a lower-confidence inventory that says so over a hard stop, and it can afford that preference precisely because `strategy` travels with every record and the model is told to verify signatures against source anyway.

One consequence deserves naming. Because rung failures are silent and detection errors are discarded (bin/diataxis:201-202), a subtly broken adapter looks exactly like a language that is not present, and a broken native rung looks exactly like tooling that is not installed. The `strategy` field is the only surface where that difference shows up, which is a good argument for reading it when an inventory looks thinner than you expected.

## Go always uses the awk pass, and that is not a gap

Go breaks the ladder pattern, and it is the most instructive adapter in the set. `go doc -all` exists, is authoritative, ships with the toolchain, and is not used. The header comment gives the reason without hedging: `go doc -all` carries no file or line information, which the citation contract needs (lib/adapters/go.sh:22-26).

That one sentence resolves what otherwise looks like an inconsistency. The harness does not want the best available description of a symbol. It wants a description anchored to a location, because every generated page's citations are checked against real source positions, and a citation without a path and a line has nothing to check. `verify_citations` resolves each citation's file, then its line range against the file's actual length (bin/diataxis:275-293). A symbol the harness cannot place is a symbol it cannot cite, and an uncitable symbol is worse than useless in a page that will be verified.

So Go's extraction is always an awk pass over exported declarations, which reads `FNR` and `FILENAME` and therefore always produces a path and a line (lib/adapters/go.sh:32-83). The toolchain still contributes, in a smaller role: when `go` is present and `go list ./...` succeeds, the module has been validated and the strategy becomes `go-list+grep` rather than plain `grep` (lib/adapters/go.sh:27-31). The native tool raises confidence in the record without producing the record.

Generalize it and you have the rule the harness actually follows: prefer a native extractor when it emits positions, and prefer a text pass when it does not. Rust's rustdoc path qualifies because the JSON index carries `span.filename` and `span.begin` (lib/adapters/rust.sh:62-63). TypeScript's typedoc path qualifies because it carries `sources[0].fileName` and `sources[0].line` (lib/adapters/typescript.sh:45-55). Python's `griffe` path qualifies through `filepath` and `lineno` (lib/adapters/python.sh:81-82). The Go deviation is not an exception to the design; it is the design stated in the negative.

## What this architecture buys and what it costs

The payoff is that adding a language means writing one file with four functions and adding one word to a loop, with no interface to learn beyond an NDJSON record shape. The reference side of the plan then falls out mechanically: `derive_reference_pages` groups the inventory by directory and emits one reference page per module, with the plan model asked to confirm coverage rather than re-derive it (bin/diataxis:410-435). An adapter that produces good records gets a reference structure for free.

The cost is that a language's understanding of itself is bounded by what one shell function can extract. Records are flat, so nothing expresses that a Go method belongs to its receiver type or that a Rust function belongs to an `impl` block, even though both adapters detect those forms well enough to classify them. Cross-file relationships, call graphs, and re-export chains sit outside the format entirely.

The `kind` vocabulary shows the same bound from a different angle. Each adapter normalizes into a shared set, and the mappings are opinionated: Rust `trait` and Go `interface` both become `interface`, Rust `enum` becomes `type`, `static` becomes `variable` (lib/adapters/rust.sh:111-118, lib/adapters/go.sh:60-72). A Rust `enum` is not really a type alias, and flattening it into `type` loses something a Rust developer cares about. The harness accepts that loss so the plan and audit logic can treat all five languages uniformly.

Visibility is where adapters differ most, because languages differ most there. Go reads capitalization (lib/adapters/go.sh:46). Rust reads the `pub` keyword and distinguishes crate visibility (lib/adapters/rust.sh:95-99). Python honors `__all__` when present and otherwise falls back to the leading-underscore convention (lib/adapters/python_ast.py:38-58). Shell has no visibility system at all, so the adapter declares a convention, that a leading underscore means internal, and applies it (lib/adapters/shell.sh:91). Inventing a convention is a defensible move for a language that never had one, and it is worth knowing that the harness did so rather than discovered it.

## Tradeoffs

| Decision | Chose | Rejected | Because |
| --- | --- | --- | --- |
| How adapters plug into the harness | Four fixed function names in a shell file, sourced inside a subshell by `run_adapter` | A plugin system with registration, discovery, and interface versioning, which the README lists as an explicit anti-goal | The subshell already supplies the isolation a plugin loader would exist to provide, and a closed set of five adapters gains nothing from version negotiation while paying for a loader and its failure modes |
| How a workspace's language is chosen | A fixed-order first-match ladder over five `adapter_detect` predicates, with shell last | Scoring adapters by confidence, or letting several adapters share one directory | Build-manifest tests are decisive enough that ranking adds no information, and shell's predicate is true of nearly every repository, so ordering alone prevents it from claiming workspaces that belong to another language |
| What happens when native symbol tooling is missing or fails | Fall to the next rung, record the lower-confidence strategy on every record, and finish the run | Failing the run, or silently emitting an unlabeled inventory that looks native | Refusing to document a crate without a nightly toolchain would make the harness unusable in the stable-only environments where generation actually runs, and a labeled approximate inventory lets the model calibrate how much it verifies |
| How Go symbols are extracted | An awk pass over exported declarations always, with `go list ./...` used only to validate the module and upgrade the recorded strategy | `go doc -all`, the authoritative tool that ships with the toolchain | `go doc -all` emits no file or line positions, and the citation contract verifies every citation against a real source location, so a symbol the harness cannot place is a symbol it cannot cite |
| How the `strategy` field is consumed | Ship it to the model inside the reference prompt as a confidence signal, alongside an instruction to verify signatures against source | Branching harness logic on strategy, for example downgrading findings or skipping pages for grep-derived inventories | Confidence in a signature is a judgment about prose fidelity rather than a deterministic rule, and the harness reserves code-driven decisions for fields with crisp semantics such as `visibility` |

## Open questions

- How does a sixth language enter a set that is closed on purpose? Today it takes a pull request adding `lib/adapters/<lang>.sh` and one word to the loop in `detect_adapter`, which works for the harness's own maintainers and offers nothing to a repository with an in-house language or a private dialect.
- Nothing in the harness reads `strategy`. If a grep-derived inventory really is lower confidence, arguments exist for making `audit` or `check` treat its findings differently, or for surfacing the mix of strategies in a run summary so you notice when a native rung quietly stopped working.
- Detection failures and native-rung failures are both silent, since `detect_adapter` discards adapter errors and each rung returns nonzero without explanation. A broken adapter is therefore indistinguishable from an absent language, and whether `doctor` should report the chosen adapter and strategy per workspace is unsettled.
- The shell adapter reads the first line of every tracked file to find extensionless scripts, both during detection and while listing sources. On a large repository that is a lot of `head` calls, and no measurement exists to say whether it matters.
- Python's best rung, `griffe dump`, takes a package name discovered from directories containing `__init__.py`, which ties inventory quality to a resolvable package layout rather than to source alone. How often that rung falls through on real projects has not been measured.
- Flattening every language into one `kind` vocabulary loses distinctions their developers care about, such as a Rust `enum` becoming `type`. Whether to add a language-native `kind_raw` field alongside the normalized one, so pages can be precise without breaking uniform tooling, is an open call.
- Inventory records are flat, so receiver-to-method and `impl`-to-function relationships never reach the reference prompt even where the adapter detects them. Adding a parent field would improve reference structure and would also expand a contract that has stayed deliberately small.

## Related

- [tutorials/write-a-language-adapter](../tutorials/write-a-language-adapter.md)
- [how-to/configure-a-multi-language-monorepo](../how-to/configure-a-multi-language-monorepo.md)
- [reference/lib/adapters](../reference/lib/adapters.md)
- [explanation/why-posix-shell-and-jq](../explanation/why-posix-shell-and-jq.md)
- [explanation/the-diataxis-mode-contract](../explanation/the-diataxis-mode-contract.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [explanation/audit-versus-check](../explanation/audit-versus-check.md)

