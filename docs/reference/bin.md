---
title: "bin reference"
slug: reference/bin
mode: reference
generated_by: diataxis
generated_at: 2026-07-29T21:42:55Z
frozen: false
---

# bin reference

Diataxis harness command-line interface. Orchestrates documentation generation, validation, and maintenance across a codebase using the Claude API. Supports language adapters, cost control, concurrent page generation, and Diataxis-mode compliance auditing.

## `diataxis`

*cli_flag*

```
diataxis [global flags] <subcommand> [subcommand flags]
```

Vendorable documentation harness that drives the Claude CLI to produce and maintain Diataxis-structured documentation for a codebase.

| Parameter | Type | Description |
| --- | --- | --- |
| `--config PATH` (optional) | `string` | Path to config file (default: <repo>/diataxis.config.json) |
| `--budget-usd N` (optional) | `number` | Spend ceiling for this run (default: config budget_usd) |
| `--concurrency N` (optional) | `integer` | Number of parallel page generations, capped at 4 (default 1) |
| `--dry-run` (optional) | `flag` | Print exact claude argv without executing |
| `--verbose` (optional) | `flag` | Chatty progress on stderr |
| `--json` (optional) | `flag` | Machine-readable status on stdout |
| `--no-color` (optional) | `flag` | Disable colored output |
| `--mode tutorial|howto|reference|explanation|all` (optional) | `string` | Documentation mode to operate on (default: all) |
| `--page PATH` (optional) | `string` | Target a single page by slug or path |
| `--force` (optional) | `flag` | Overwrite hand-edited pages or remove unverified content |

Raises:
- EX_GENERIC - invalid arguments, missing config, environment problems, or model failures
- EX_AUDIT_FAILED - check found audit rule violations
- EX_STALE - check found stale pages needing regeneration
- EX_VERIFY_FAILED - check found unverified tutorials

Source: `bin/diataxis` (lines 1-5)

## `doctor`

*cli_flag*

```
diataxis doctor
```

Check environment and authentication, probe configured models for availability.

Source: `bin/diataxis` (lines 347-368)

## `init`

*cli_flag*

```
diataxis init
```

Detect code language, write diataxis.config.json, and scaffold docs/ directory structure.

Source: `bin/diataxis` (lines 382-406)

## `plan`

*cli_flag*

```
diataxis plan
```

Produce or refresh the documentation inventory from source code. Derives reference pages mechanically and builds tutorial/howto/explanation entries via Claude.

Source: `bin/diataxis` (lines 437-500)

## `generate`

*cli_flag*

```
diataxis generate [--mode M] [--page PATH] [--force]
```

Generate pages from the plan. Respects frozen pages, detects staleness, verifies tutorial code, and repairs failed tutorials.

Source: `bin/diataxis` (lines 773-894)

## `audit`

*cli_flag*

```
diataxis audit [--page PATH]
```

Diataxis compliance review of existing documentation. Applies local rules (staleness, broken citations, orphan pages) and model-based Diataxis rubric assessment.

Source: `bin/diataxis` (lines 1043-1064)

## `check`

*cli_flag*

```
diataxis check
```

CI mode: non-zero exit if any page is stale, audit fails, or unverified tutorials exist. Outputs JSON or human-readable findings.

Source: `bin/diataxis` (lines 1068-1120)

## `cost`

*cli_flag*

```
diataxis cost
```

Print spend summary from the manifest, aggregated by mode and model.

Source: `bin/diataxis` (lines 1124-1144)

## `clean`

*cli_flag*

```
diataxis clean
```

Remove generated pages no longer in the plan, respecting frozen pages and hand-edits.

Source: `bin/diataxis` (lines 1148-1181)

## `DIATAXIS_ROOT`

*constant*

```
DIATAXIS_ROOT=$(CDPATH='' cd -- "$(dirname -- "$prg")/.." && pwd)
```

Absolute path to the harness root directory, resolved from the location of the diataxis script.

Source: `bin/diataxis` (lines 17)

## `PROMPT_VERSION_TUTORIAL`

*constant*

```
PROMPT_VERSION_TUTORIAL=1
```

Prompt version for tutorial mode. Bumping this invalidates every tutorial page, forcing regeneration.

Source: `bin/diataxis` (lines 27)

## `PROMPT_VERSION_HOWTO`

*constant*

```
PROMPT_VERSION_HOWTO=1
```

Prompt version for how-to mode. Bumping this invalidates every how-to page, forcing regeneration.

Source: `bin/diataxis` (lines 28)

## `PROMPT_VERSION_REFERENCE`

*constant*

```
PROMPT_VERSION_REFERENCE=1
```

Prompt version for reference mode. Bumping this invalidates every reference page, forcing regeneration.

Source: `bin/diataxis` (lines 29)

## `PROMPT_VERSION_EXPLANATION`

*constant*

```
PROMPT_VERSION_EXPLANATION=1
```

Prompt version for explanation mode. Bumping this invalidates every explanation page, forcing regeneration.

Source: `bin/diataxis` (lines 30)

## `DIATAXIS_CONFIG`

*variable*

```
DIATAXIS_CONFIG=''
```

Path to diataxis.config.json, set via --config flag.

Source: `bin/diataxis` (lines 62)

## `DIATAXIS_BUDGET_USD`

*variable*

```
DIATAXIS_BUDGET_USD=${DIATAXIS_BUDGET_USD:-}
```

Spend ceiling in USD for this run, set via --budget-usd flag or inherited from environment.

Source: `bin/diataxis` (lines 63)

## `DIATAXIS_CONCURRENCY`

*variable*

```
DIATAXIS_CONCURRENCY=1
```

Number of pages to generate in parallel, set via --concurrency flag (capped at 4).

Source: `bin/diataxis` (lines 64)

## `DIATAXIS_DRY_RUN`

*variable*

```
DIATAXIS_DRY_RUN=0
```

When set to 1 via --dry-run, print the exact claude argv without executing.

Source: `bin/diataxis` (lines 65)

## `DIATAXIS_VERBOSE`

*variable*

```
DIATAXIS_VERBOSE=0
```

When set to 1 via --verbose, emit progress messages to stderr.

Source: `bin/diataxis` (lines 66)

## `DIATAXIS_JSON`

*variable*

```
DIATAXIS_JSON=0
```

When set to 1 via --json, output machine-readable JSON status instead of human text.

Source: `bin/diataxis` (lines 67)

## `DIATAXIS_NO_COLOR`

*variable*

```
DIATAXIS_NO_COLOR=0
```

When set to 1 via --no-color, disable colored output.

Source: `bin/diataxis` (lines 68)

## `DIATAXIS_FORCE`

*variable*

```
DIATAXIS_FORCE=0
```

When set to 1 via --force, overwrite hand-edited pages during generate and remove unverified pages during clean.

Source: `bin/diataxis` (lines 69)

## `DIATAXIS_MODE`

*variable*

```
DIATAXIS_MODE=all
```

Documentation mode to operate on: tutorial, howto, reference, explanation, or all. Set via --mode flag.

Source: `bin/diataxis` (lines 70)

## `DIATAXIS_PAGE`

*variable*

```
DIATAXIS_PAGE=''
```

Target page slug or path, set via --page flag. When empty, all matching pages are operated on.

Source: `bin/diataxis` (lines 71)

## `DIATAXIS_TMPDIR`

*variable*

```
DIATAXIS_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/diataxis.XXXXXX")
```

Ephemeral directory for intermediate artifacts, cleaned up on exit.

Source: `bin/diataxis` (lines 125)

## `mode_to_dir`

*function*

```
mode_to_dir()
```

Convert a Diataxis mode name to its docs directory: tutorial -> tutorials, howto -> how-to, reference -> reference, explanation -> explanation.

Source: `bin/diataxis` (lines 131-139)

## `dir_to_mode`

*function*

```
dir_to_mode()
```

Convert a docs directory name to its Diataxis mode: tutorials -> tutorial, how-to -> howto, reference -> reference, explanation -> explanation. Prints empty string if unrecognized.

Source: `bin/diataxis` (lines 141-149)

## `glob_match`

*function*

```
glob_match() PATH PATTERN
```

Match a path against a shell glob pattern where ** is treated as * (crosses directory boundaries) and leading **/ matches zero or more directory levels.

| Parameter | Type | Description |
| --- | --- | --- |
| `PATH` | `string` | File path to match |
| `PATTERN` | `string` | Shell glob pattern |

Source: `bin/diataxis` (lines 158-173)

## `path_included`

*function*

```
path_included() PATH EXTRA_INCLUDE_GLOBS
```

Test whether a path is documentable: matches config include globs or adapter source globs, and no exclude glob.

| Parameter | Type | Description |
| --- | --- | --- |
| `PATH` | `string` | Workspace-relative file path |
| `EXTRA_INCLUDE_GLOBS` | `string` | Newline-separated additional include patterns |

Source: `bin/diataxis` (lines 179-194)

## `detect_adapter`

*function*

```
detect_adapter() WS_RELPATH
```

Detect the language adapter applicable to a workspace: rust, go, python, typescript, or shell. Prints adapter name or nothing if none match.

| Parameter | Type | Description |
| --- | --- | --- |
| `WS_RELPATH` | `string` | Workspace-relative path |

Source: `bin/diataxis` (lines 199-208)

## `run_adapter`

*function*

```
run_adapter() ADAPTER WS_RELPATH FUNC
```

Run one adapter function in a subshell with cwd at the workspace.

| Parameter | Type | Description |
| --- | --- | --- |
| `ADAPTER` | `string` | Adapter name (rust, go, python, typescript, shell) |
| `WS_RELPATH` | `string` | Workspace-relative path |
| `FUNC` | `string` | Adapter function to invoke |

Source: `bin/diataxis` (lines 212-215)

## `workspaces_resolved`

*function*

```
workspaces_resolved()
```

Print one line per configured workspace, tab-separated: path, adapter, name. Auto-detected adapters are resolved once per run. Undetectable workspaces are skipped with warnings.

Source: `bin/diataxis` (lines 220-225)

## `workspace_sources`

*function*

```
workspace_sources() WS_RELPATH ADAPTER
```

List repository-relative documentable source files from a workspace, filtered by config include/exclude and adapter source globs.

| Parameter | Type | Description |
| --- | --- | --- |
| `WS_RELPATH` | `string` | Workspace-relative path |
| `ADAPTER` | `string` | Language adapter name |

Source: `bin/diataxis` (lines 246-257)

## `full_symbol_inventory`

*function*

```
full_symbol_inventory()
```

Emit NDJSON of every workspace's symbol inventory: each record has path made repository-relative, plus workspace name and adapter name.

Source: `bin/diataxis` (lines 261-269)

## `verify_citations`

*function*

```
verify_citations() STRUCTURED_JSON
```

Print one line per unresolved citation: missing file, line beyond end of file, or symbol not found in source. Empty output means all citations are valid.

| Parameter | Type | Description |
| --- | --- | --- |
| `STRUCTURED_JSON` | `string` | JSON with nested citations objects (path, line_range, symbol fields) |

Source: `bin/diataxis` (lines 275-316)

## `prompt_version_for`

*function*

```
prompt_version_for() MODE
```

Get the prompt version for a documentation mode, formatted as mode@version (e.g. tutorial@1).

| Parameter | Type | Description |
| --- | --- | --- |
| `MODE` | `string` | Documentation mode: tutorial, howto, reference, or explanation |

Source: `bin/diataxis` (lines 318-325)

## `models_equivalent`

*function*

```
models_equivalent() A B
```

Test whether two model names are equivalent: same name, or one is the other with a trailing YYYYMMDD suffix (dated model variants).

| Parameter | Type | Description |
| --- | --- | --- |
| `A` | `string` | First model name |
| `B` | `string` | Second model name |

Source: `bin/diataxis` (lines 328-337)

## `plan_pages_filtered`

*function*

```
plan_pages_filtered()
```

Print plan entries matching --mode and --page, one JSON per line.

Source: `bin/diataxis` (lines 505-517)

## `tutorial_extract_blocks`

*function*

```
tutorial_extract_blocks() STRUCTURED WORKDIR
```

Write step-N.sh scripts for every executable fenced code block in a tutorial, replacing scripts from prior attempts. Extracts commands from console blocks (lines starting with $ ).

| Parameter | Type | Description |
| --- | --- | --- |
| `STRUCTURED` | `string` | Structured tutorial JSON with steps |
| `WORKDIR` | `string` | Working directory where step scripts are written |

Source: `bin/diataxis` (lines 521-540)

## `tutorial_verify`

*function*

```
tutorial_verify() STRUCTURED WORKDIR
```

Run every executable block in order in an ephemeral directory. Returns a failure report (empty on success), or runs through a sandbox if configured.

| Parameter | Type | Description |
| --- | --- | --- |
| `STRUCTURED` | `string` | Structured tutorial JSON with steps |
| `WORKDIR` | `string` | Working directory for tutorial execution |

Source: `bin/diataxis` (lines 545-573)

## `generate_one_page`

*function*

```
generate_one_page() PAGE_JSON OUTDIR
```

Worker process that generates one page. Produces OUTDIR/meta.json with status and cost. On success, produces OUTDIR/page.md. Handles tutorial verification and repair. Never writes to the repository.

| Parameter | Type | Description |
| --- | --- | --- |
| `PAGE_JSON` | `string` | Plan entry (slug, mode, title, sources, etc.) as JSON |
| `OUTDIR` | `string` | Output directory for artifacts |

Source: `bin/diataxis` (lines 577-714)

## `apply_page_result`

*function*

```
apply_page_result() OUTDIR
```

Parent-side merge of one worker's output. Owns every write to the repository. Sets APPLY_STATUS. Must run in parent shell (not a command substitution) so budget accounting works.

| Parameter | Type | Description |
| --- | --- | --- |
| `OUTDIR` | `string` | Worker output directory |

Source: `bin/diataxis` (lines 719-771)

## `local_findings`

*function*

```
local_findings()
```

Emit audit findings from deterministic rules: staleness, broken citations, orphaned pages, and missing reference documentation. No model call required.

Source: `bin/diataxis` (lines 900-997)

## `model_findings`

*function*

```
model_findings() TARGETS
```

Apply the Diataxis rubric to each page via Claude, assessing compliance with Diataxis mode contracts.

| Parameter | Type | Description |
| --- | --- | --- |
| `TARGETS` | `string` | Newline-separated list of documentation paths to audit |

Source: `bin/diataxis` (lines 1000-1024)

## `audit_targets`

*function*

```
audit_targets()
```

Print documentation paths to audit: single page if --page is set, otherwise all pages under docs/.

Source: `bin/diataxis` (lines 1026-1041)

## `derive_reference_pages`

*function*

```
derive_reference_pages() INVENTORY_FILE
```

Derive reference page plan entries mechanically from the symbol inventory, one page per module, mirroring the source tree.

| Parameter | Type | Description |
| --- | --- | --- |
| `INVENTORY_FILE` | `string` | Path to NDJSON file of symbols |

Source: `bin/diataxis` (lines 413-435)

## `preflight`

*function*

```
preflight()
```

Quiet doctor check, config load, and bare-mode resolution. Used before every subcommand except doctor.

| Parameter | Type | Description |
| --- | --- | --- |
| `OPTIONAL` | `integer` | When 1, config is optional; when 0 or omitted, config is required |

Source: `bin/diataxis` (lines 372-378)

