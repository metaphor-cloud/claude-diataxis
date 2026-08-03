# diataxis

A vendorable documentation harness that drives the Claude CLI (`claude`) to
produce and maintain [Diataxis](https://diataxis.fr/)-structured documentation
(tutorials, how-to guides, reference, explanation) for a codebase. It drops
into Rust, Go, Python and TypeScript repositories with no per-language runtime
dependency.

- Implementation language is POSIX shell, Bash 3.2 compatible.
- Runtime dependencies: `claude`, `jq` (>= 1.6), `git`, coreutils. Nothing else.
- Config is JSON; `jq` is the only parser.
- **The harness owns the filesystem. Claude never writes files.** Every
  generation call runs read-only (`--allowedTools "Read,Grep,Glob"`), returns
  structured JSON validated against a schema, and the shell writes the result
  to disk. Runs are reviewable, diffable and idempotent, and a prompt
  injection in a source comment cannot write to your tree.
- Every invocation pins a model explicitly. Deterministic in CI: same inputs,
  same manifest, no work done.

## Install

Vendoring is the primary path: the `diataxis/` directory is committed into
your repository.

```sh
# from a checkout of this repo
path/to/claude-diataxis/install.sh path/to/your-repo

# or via curl
curl -fsSL <raw-url>/install.sh | DIATAXIS_REPO_URL=<this repo's git url> sh
```

`git subtree add --prefix diataxis <url> main --squash` and git submodules
work equally well.

## Quick start

```sh
diataxis/bin/diataxis doctor    # environment and auth checks
diataxis/bin/diataxis init     # detect language, write config, scaffold docs/
diataxis/bin/diataxis plan     # produce the page inventory (review the diff!)
diataxis/bin/diataxis generate # write the pages
diataxis/bin/diataxis check    # CI gate: stale or failing docs exit non-zero
```

## CLI surface

```
diataxis doctor                 # environment + auth checks, exit 0 or 1
diataxis init                   # detect language, write diataxis.config.json, scaffold docs/
diataxis plan                   # produce/refresh the page inventory, no prose written
diataxis generate [--mode M] [--page PATH] [--force]
diataxis audit [--page PATH]    # Diataxis compliance review of existing docs
diataxis check                  # CI mode: non-zero if stale or failing audit, writes nothing
diataxis cost                   # spend summary from the manifest
diataxis clean                  # remove generated pages no longer in the plan
```

Global flags: `--config PATH`, `--budget-usd N`, `--concurrency N` (default 1,
cap 4), `--dry-run`, `--verbose`, `--json`, `--no-color`. `--mode` accepts
`tutorial`, `howto`, `reference`, `explanation`, or `all` (default).
`generate --priority N` limits generation to plan pages of priority N and
better (1 is highest), so a budgeted run spends on what matters first.

`--dry-run` prints the exact `claude` argv (first line `claude`, one argument
per line, blank-line terminated) without executing anything. Every test that
touches model selection asserts against that argv.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | success |
| 1 | generic failure (bad arguments, failed generation) |
| 2 | config invalid (message includes the offending JSON pointer) |
| 10 | `claude` missing from PATH |
| 11 | `claude` older than 2.1.205 |
| 12 | unauthenticated |
| 13 | `jq` missing or older than 1.6 |
| 14 | `git` missing or not inside a work tree |
| 15 | `docs/` or `.diataxis/` not writable |
| 16 | bare-capable auth required but unavailable |
| 20 | budget exceeded |
| 21 | model unavailable or not permitted |
| 30 | audit failed in `check` |
| 31 | staleness detected in `check` |
| 32 | tutorial verification failed in `check` |

Codes 14, 15 and 16 are additions beyond the original specification so that
every doctor check has a distinct exit code.

## Model routing

Routing is by the judgment a mode requires, not output length. Ship defaults
(override in `diataxis.config.json`):

| Mode | Model | Effort |
| --- | --- | --- |
| plan | claude-opus-5 | high |
| tutorial | claude-opus-5 | high |
| explanation | claude-opus-5 | high |
| howto | claude-sonnet-5 | medium |
| reference | claude-sonnet-5 | medium |
| reference bulk pass | claude-haiku-4-5 | (none) |
| audit | claude-sonnet-5 | medium |

Opus calls carry `--fallback-model claude-sonnet-5` so overload does not fail
a run. The model that actually answered is recorded per page from the
`modelUsage` breakdown; if it differs from the requested model (fallback
engaged), `check` marks the page stale rather than accepting silently.
Reference pages with 25 or more inventory symbols route to the
`reference_bulk` model, since converting an already-extracted symbol list to
prose is Haiku work.

Use exact model ids in config, not family aliases, so output does not shift
when a new family member ships. Fable-tier models are deliberately not used:
double the Opus price with no benefit for this workload.

## The bare mode gotcha

`--bare` makes runs reproducible: it skips hooks, skills, plugins, MCP
servers, `CLAUDE.md` and auto memory, so a teammate's `~/.claude` cannot
change your output. But bare mode also skips OAuth and keychain reads, so it
only works when auth comes from `ANTHROPIC_API_KEY`,
`CLAUDE_CODE_OAUTH_TOKEN`, or an `apiKeyHelper` via a settings file.

Resolution (config key `bare`: `"auto"` (default) | `true` | `false`):

- Env credential auth: `--bare` is passed.
- Subscription keychain login: `--bare` is omitted, with a one-line warning
  that local `CLAUDE.md` and hooks will be in context, so output may not
  match CI.
- `diataxis check` requires bare-capable auth and fails loudly (exit 16)
  otherwise. CI must be reproducible.

Note: the installed CLI's `--bare` help text says auth is strictly
`ANTHROPIC_API_KEY` or `apiKeyHelper` via `--settings`; the contract here
also treats `CLAUDE_CODE_OAUTH_TOKEN` as bare-capable, matching
`claude setup-token` guidance for CI. If your CLI version rejects the token
in bare mode, set `"bare": false` or use an API key.

Independently of `--bare`, every call passes `--strict-mcp-config` (with no
`--mcp-config`), so ambient MCP servers never load. The harness only allows
Read, Grep and Glob; a half-configured or policy-blocked MCP server in your
user config would otherwise be noise at best and a failed run at worst.

## How it works

### Plan

`diataxis plan` reads the repository (source list, symbol inventory, context
files, git history, existing docs) and writes `.diataxis/plan.json`: the page
inventory, one mode per page, with a one-line rationale each. The plan is a
diffable artifact under review. `plan` never writes prose, and `generate`
never invents pages that are not in the plan.

Reference pages are derived mechanically by the harness from the symbol
inventory (one page per module, mirroring the source tree) and merged into
the plan; the plan model is instructed not to re-derive them. A plan that
wants more than three tutorials is flagged.

### Generate

For each stale planned page, the harness renders a task prompt (file paths,
not piped content), invokes `claude` read-only with a JSON Schema, verifies
that every citation resolves to a real source location (a page whose
citations do not resolve is a failed generation, not a warning), renders
Markdown through a shell template, and writes the page plus a manifest entry.

- How-to guides have exactly one goal. If the plan handed a page two goals,
  the model returns `{"split": [...]}`, the harness amends the plan, and the
  next `generate` produces the split pages.
- Tutorials get a mandatory verification pass: every fenced block whose
  language is in `verify.executable_languages` is executed in order in an
  ephemeral directory, wrapped by `verify.sandbox_command` so model-authored
  shell runs confined rather than with your full authority. On failure a
  repair call runs with the failure output appended,
  capped at `verify.max_repairs` (default 2). Unverified tutorials are
  written with `verified: false` frontmatter and `check` fails on them unless
  `verify.required` is false.

### Manifest, hashing, idempotency

`.diataxis/manifest.json` is committed, one entry per page. `inputs_hash`
covers, in stable order: the content of every source file listed for the
page, the system prompt, the task template, the schema, the config's model
block, and the plan entry. Any change makes the page stale; regeneration is
skipped otherwise unless `--force`.

`content_hash` detects human edits. If the file on disk differs from what was
generated (or exists without ever having been generated), it is never
overwritten: the harness warns and requires `--force`, or a `frozen: true`
frontmatter key to keep the page permanently. Frozen pages are never
regenerated or cleaned, even with `--force`.

Cost: each call's `total_cost_usd` accumulates in the manifest.
`--budget-usd` (or config `budget_usd`, default 50) refuses to start a call
once the run's spend reaches the budget, reporting the shortfall rather than
half-generating, and the remaining budget is also passed per call as
`--max-budget-usd` as a second belt. Completed pages are recorded in the
manifest, so a run that dies on budget resumes where it left off.

### Understanding and managing cost

What the numbers mean:

- The harness accumulates the CLI's own `total_cost_usd`, which includes
  prompt-cache creation. Every call carries the Claude Code preamble
  (roughly 30k tokens), so expect a baseline of a few cents per call before
  any real work. On subscription auth the figure is notional API cost, not
  a bill.
- The budget is **per run**, not per project. Hitting it is not a failure:
  re-running `generate` continues from the manifest with a fresh allowance.
  A large plan is expected to take several budgeted runs.
- A call killed mid-flight by the per-call `--max-budget-usd` belt reports
  no usage, so its spend is not recorded. Treat manifest totals as a floor.

What actually drives cost, in order:

1. **Page count.** Each page is a fresh agentic session that explores the
   repository. Review `.diataxis/plan.json` and cut or demote pages before
   generating; the plan is the cheapest place to save money. The plan
   prompt is instructed to be economical and to use priorities honestly.
2. **Opus pages.** Explanation and tutorial pages run 1 to 2 dollars each
   at the default routing. `generate --priority 1` first, then widen.
   Routing explanation to `claude-sonnet-5` in the models block is a
   legitimate trade if your budget is tight.
3. **Exploration turns.** `models.MODE.max_turns` caps how long a call can
   wander (default 24; the reference bulk pass defaults to 12 because its
   symbols arrive inline). Lowering howto/reference to 12 to 16 turns cuts
   cost on repositories with well-named sources.
4. **Ambient context.** Without `--bare` (subscription auth), your global
   and project `CLAUDE.md`, skills and plugins ride along in every call.
   CI runs with `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` are
   cheaper per call as well as reproducible.
5. **Repair loops.** A tutorial that cannot verify in a bare sandbox burns
   its Opus repair attempts every regeneration. The default sandbox denies
   network access, so a tutorial that fetches anything will fail on every
   attempt. If your tutorials need project dependencies or the network, point
   `verify.sandbox_command` at a container image that provides them, or accept
   `verified: false` with `verify.required: false`.
6. **Stale cascades.** Editing a source file regenerates every page that
   lists it. Keep plan `sources` narrow, and use `generate --page` while
   iterating on one page.

### Audit and check

`diataxis audit` reviews existing docs (including hand-written ones) against
a fixed rubric: `mode_mixing`, `title_not_task_shaped`, `unverified_code`,
`broken_citation`, `stale`, `orphan`, `missing_reference`. It reports
findings and exits 0; severity mapping applies in `check`.

`diataxis check` is the CI gate. It writes nothing and computes the
deterministic rules locally without model calls (`stale`, `broken_citation`,
`orphan`, `missing_reference`, unverified tutorials, model divergence).
Rules that need judgment (`mode_mixing`, title shape) run in `diataxis
audit`, which calls the model; set `audit.model_audit_in_check: true` to run
those in `check` too. Findings at severities in `audit.fail_on` (default
`["error"]`) exit 30; staleness exits 31; unverified tutorials exit 32.

## Configuration

`diataxis.config.json` at the repo root, validated against
`schemas/config.json` on load; violations fail with the offending JSON
pointer. See `share/diataxis.config.example.json` for every key and default.

- `workspaces`: multi-language monorepos compose adapters; run detection per
  directory and namespace slugs by workspace `name`.
- `voice.style_guide`: `google` or `microsoft`; injects sentence-case
  headings, second person, present tense, no "simply" or "just", spelled-out
  first-use acronyms into every system prompt.
- `verify.sandbox_command`: wrapper for tutorial verification (receives the
  step script path as its final argument). The starter config points this at
  `$DIATAXIS_ROOT/share/sandbox/verify-sandbox.sh`, which confines each step
  with `sandbox-exec` on macOS or `bwrap` on Linux: no network, no writes
  outside the verification directory, no writes into the harness's own run
  directory, and no reads of common credential paths. It exits 78 without
  running the step if neither mechanism is available rather than falling back
  to unconfined execution. A `docker run` wrapper works too. Set it to `null`
  and verification runs on the host with your full authority.

  `verify.mode: "sandbox"` on its own does not confine anything: it selects
  verification in a wiped ephemeral directory, and `sandbox_command` is what
  supplies the boundary.

## Language adapters

Each adapter exposes exactly four functions: `adapter_detect`,
`adapter_source_globs`, `adapter_symbol_inventory` (NDJSON:
`{name, kind, signature, path, line, visibility, doc_comment, strategy}`),
`adapter_context_files`.

| Language | Detection | Native path | Fallback |
| --- | --- | --- | --- |
| Rust | `Cargo.toml` | `cargo +nightly rustdoc` JSON | `cargo metadata` + grep over `pub` items |
| Go | `go.mod` | `go list ./...` validates the module | awk over exported declarations |
| Python | `pyproject.toml` / `setup.py` | `griffe dump`, else the bundled `ast` script | grep over `def`/`class` |
| TypeScript | `package.json` + `tsconfig.json` | `typedoc --json` | grep over `export` declarations |
| Shell | tracked `*.sh`/`*.bash`, or `bin/` scripts with a shell shebang | (none exists) | awk over function definitions and top-level constants |

The shell adapter detects last: most repositories contain some shell, so it
only claims a workspace no other adapter recognises. Convention: names with
a leading underscore are internal.

Missing native tooling never fails a run; the strategy used is recorded on
every inventory record, because a grep-derived inventory is lower confidence.
Note the Go deviation: `go doc -all` carries no file/line positions, which
the citation contract requires, so extraction is always the awk pass and
`go list` is used for validation only.

## CI integration

Ship-ready snippets live in `share/integrations/`:

- `github-actions-docs-check.yml`: a PR job that runs `diataxis check` only,
  with `CLAUDE_CODE_OAUTH_TOKEN` from secrets, and posts findings as PR
  annotations.
- `Makefile.diataxis`, `justfile`, `package.json.snippet`, `xtask-docs.rs`:
  thin wrappers over `bin/diataxis`.

**Generation does not belong in PR CI.** It costs money and produces prose
that needs human review. Run `diataxis generate` from a manually dispatched
or scheduled workflow (or locally), commit the diff, and review it like any
other change. `diataxis check` on every PR then keeps the committed docs
honest.

## Testing

```sh
shellcheck -s sh bin/diataxis lib/*.sh lib/adapters/*.sh tests/helpers/claude install.sh share/sandbox/verify-sandbox.sh
bats tests/
```

- The bats suite stubs `claude` as a PATH shim on a hermetic sandbox PATH; no
  live calls, no credentials. It covers every preamble failure path and exit
  code, config validation, hash staleness, cost accumulation, human-edit
  protection, tutorial verification and repair, the how-to split contract,
  and golden `plan.json` comparisons for all four fixture repos.
- `tests/tutorial.bats` asserts step extraction end to end: the step scripts
  themselves fail unless their code arrived byte-intact, so a page reaching
  `verified: true` is the proof. It also drives
  `share/sandbox/verify-sandbox.sh` directly to check that writes outside the
  verification directory, writes into the harness run directory, and network
  access are all denied, and that the wrapper fails closed. Those cases skip
  on hosts with neither `sandbox-exec` nor `bwrap`.
- One live smoke test is opt-in behind `DIATAXIS_LIVE=1`, capped at
  `--budget-usd 0.50`.
- Shellcheck ignore list (documented): `SC1090` (adapters are sourced through
  a variable path by design; the adapter set is closed and each file is
  checked individually), plus inline disables where word splitting or
  unquoted case patterns are the point (`SC2086`, `SC2254`) and one inline
  `SC2012` where `ls` iterates harness-generated filenames.

## Decisions and deviations

Recorded here per the build contract ("decide and note it in the README"):

1. Exit codes 14, 15, 16 added so every doctor check is distinct (the
   original list only defined 10-13 and 20+).
2. Layout additions: `lib/render.sh` (Markdown renderers),
   `lib/adapters/python_ast.py` (the "ast one-liner" as a real file, so it is
   lintable), `.shellcheckrc`, `tests/helpers/`, `.github/workflows/ci.yml`.
3. `--json-schema` is inlined via `jq -c` (the installed CLI, 2.1.220,
   documents inline JSON only; no `@file` form).
4. `--append-system-prompt-file` and `--max-turns` are undocumented in
   `claude --help` on 2.1.220 but parse and work; both are used.
5. Voice conventions are appended to a merged copy of the system prompt in a
   temp directory, keeping `prompts/system/*` pristine.
6. Reference plan entries are derived mechanically by the harness before the
   plan call; the plan model is told to confirm coverage only.
7. `doctor` probes model permissions live only when `DIATAXIS_LIVE=1`,
   because doctor runs inside every subcommand and must stay fast and free.
8. `check` runs the deterministic local rule subset by default;
   `audit.model_audit_in_check` opts model rules into CI.
9. `audit` always exits 0 (it is a reporting tool); severities map to exit
   behaviour in `check` via `audit.fail_on`.
10. A page that exists on disk but was never generated by diataxis is treated
    like a human edit: never overwritten without `--force`.
11. Concurrency is implemented in batches; workers only write to a temp
    directory and the parent applies all repository writes and manifest
    updates serially.
12. `clean` deletes only pages tracked in the manifest; orphan hand-written
    pages are reported by `audit`/`check`, never deleted.
13. Budget enforcement refuses to start a call once accumulated run spend
    reaches the budget (call cost is unknowable in advance); the remaining
    budget is passed per call as `--max-budget-usd`.
14. A fifth adapter, `shell`, was added beyond the specified four so the
    harness can document repositories like itself. It detects last (most
    repositories contain some shell) and its inventory is always grep-derived
    since no native symbol tooling exists for shell.
15. Every call passes `--strict-mcp-config` so ambient MCP servers never
    load, even when subscription auth forces a run without `--bare`. Found
    by dogfooding: a policy-blocked claude.ai MCP server failed a generation
    that never needed MCP at all.

## Anti-goals

No static site generator, no theme, no search index, no web UI, no plugin
system, no language runtime dependency. Output is plain Markdown with YAML
frontmatter that MkDocs, Docusaurus, mdBook and Hugo can all consume.
