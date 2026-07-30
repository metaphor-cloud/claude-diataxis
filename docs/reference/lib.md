---
title: "lib reference"
slug: reference/lib
mode: reference
generated_by: diataxis
generated_at: 2026-07-29T21:43:49Z
frozen: false
---

# lib reference

Shell function reference for lib/claude.sh, lib/config.sh, lib/manifest.sh, lib/preamble.sh and lib/render.sh: the harness's model invocation, configuration, manifest/staleness, environment checks and Markdown rendering layers.

## `claude_files_mode`

*function*

```
claude_files_mode MODE
```

Prints the prompt/schema file basename a mode uses. Maps `reference_bulk` to `reference` since both share the reference contract; any other mode prints unchanged.

| Parameter | Type | Description |
| --- | --- | --- |
| `MODE` | `string` | The generation mode name. |

Returns: The file-basename mode, printed to stdout followed by a newline.

Source: `lib/claude.sh` (lines 8-13)

## `claude_system_prompt_file`

*function*

```
claude_system_prompt_file MODE
```

Materializes the merged system prompt file for a mode (base prompt plus configured voice conventions) once per run, caching it under `$DIATAXIS_TMPDIR`, and prints its path.

| Parameter | Type | Description |
| --- | --- | --- |
| `MODE` | `string` | The generation mode name. |

Returns: Absolute path to the merged system prompt file, printed to stdout followed by a newline.

Source: `lib/claude.sh` (lines 17-27)

## `claude_run`

*function*

```
claude_run MODE MAX_TURNS OUT_FILE TASK_PROMPT
```

Builds the full `claude` CLI argument vector for a mode (pinned model, effort, appended system prompt, read-only allowed tools, dontAsk permission mode, strict MCP config, JSON output and schema, max turns, opus fallback model, remaining-budget cap, optional settings file, optional `--bare`) and either executes it or, under `--dry-run`, prints the argv one argument per line. On execution, writes the CLI's JSON result to OUT_FILE, accumulates cost via `budget_add`, and logs timing and cost.

| Parameter | Type | Description |
| --- | --- | --- |
| `MODE` | `string` | The generation mode name (e.g. tutorial, howto, reference, explanation, audit). |
| `MAX_TURNS` | `integer` | Maximum agent turns passed as `--max-turns`. |
| `OUT_FILE` | `path` | Path the CLI's JSON output is written to. |
| `TASK_PROMPT` | `string` | The task prompt passed as the final positional argument. |

Returns: 0 on success (or on printing the dry-run argv).

Raises:
- EX_CONFIG when no model is configured for MODE
- EX_MODEL_UNAVAILABLE when the API rejects the configured model
- EX_BUDGET when the per-call `--max-budget-usd` cap is hit
- EX_GENERIC when `claude` exits non-zero for any other reason, returns non-JSON output, or reports `is_error: true`

Source: `lib/claude.sh` (lines 38-131)

## `claude_structured`

*function*

```
claude_structured OUT_FILE
```

Prints the validated `.structured_output` field from a `claude_run` result file. Empty output indicates the call failed to produce schema-conforming output.

| Parameter | Type | Description |
| --- | --- | --- |
| `OUT_FILE` | `path` | The JSON result file written by claude_run. |

Returns: The structured output JSON, printed compactly to stdout, or nothing on failure.

Source: `lib/claude.sh` (lines 136-138)

## `claude_cost`

*function*

```
claude_cost OUT_FILE
```

Prints a call's cost in USD from its result file's `.total_cost_usd` field, defaulting to 0.

| Parameter | Type | Description |
| --- | --- | --- |
| `OUT_FILE` | `path` | The JSON result file written by claude_run. |

Returns: The cost in USD as a string, printed to stdout.

Source: `lib/claude.sh` (lines 141-143)

## `claude_model_used`

*function*

```
claude_model_used OUT_FILE
```

Resolves the concrete model that answered a call from the `.modelUsage` breakdown, picking the entry with the highest output token count (covers alias resolution and fallback engagement).

| Parameter | Type | Description |
| --- | --- | --- |
| `OUT_FILE` | `path` | The JSON result file written by claude_run. |

Returns: The concrete model id, printed to stdout, or empty string if no usage is recorded.

Source: `lib/claude.sh` (lines 148-155)

## `config_default_json`

*function*

```
config_default_json
```

Prints the full default configuration document, kept in sync with `share/diataxis.config.example.json`.

Returns: The default config JSON, printed to stdout.

Source: `lib/config.sh` (lines 7-38)

## `config_validate_jq`

*function*

```
config_validate_jq
```

Prints a jq program implementing a JSON Schema validator for the subset used by `schemas/config.json` (type, enum, required, properties, additionalProperties, items, `$ref` resolution against `definitions`).

Returns: jq source code, printed to stdout, that emits one violation line per schema failure as `<json pointer>: <message>`.

Source: `lib/config.sh` (lines 43-101)

## `config_find_path`

*function*

```
config_find_path
```

Resolves the configuration file path: `$DIATAXIS_CONFIG` if set, otherwise `diataxis.config.json` at the workspace root if it exists.

Returns: The resolved config path, printed to stdout, or nothing when no config exists.

Source: `lib/config.sh` (lines 105-113)

## `config_load`

*function*

```
config_load [ALLOW_MISSING]
```

Loads and validates the configuration file against `schemas/config.json`, deep-merges it over `config_default_json`, and populates `DIATAXIS_CONFIG_JSON`, `DIATAXIS_CONFIG_PATH`, `DIATAXIS_DOCS_DIR`, `DIATAXIS_INCLUDE_GLOBS`, `DIATAXIS_EXCLUDE_GLOBS` and `DIATAXIS_BUDGET_USD` as exported globals.

| Parameter | Type | Description |
| --- | --- | --- |
| `ALLOW_MISSING` (optional) | `integer` | When 1, a missing config file yields the defaults instead of dying. Defaults to 0. |

Raises:
- EX_CONFIG when the resolved config path does not exist as a file
- EX_CONFIG when the config file is not valid JSON
- EX_CONFIG when the config fails schema validation
- EX_CONFIG when no config is found and ALLOW_MISSING is not 1

Source: `lib/config.sh` (lines 118-161)

## `cfg`

*function*

```
cfg [-r] FILTER
```

Queries the merged config JSON (`$DIATAXIS_CONFIG_JSON`) with a jq filter.

| Parameter | Type | Description |
| --- | --- | --- |
| `-r` (optional) | `flag` | When given as the first argument, runs jq in raw-output mode (`jq -r`); otherwise compact JSON output (`jq -c`). |
| `FILTER` | `string` | The jq filter expression. |

Returns: The jq query result, printed to stdout.

Source: `lib/config.sh` (lines 164-170)

## `cfg_model`

*function*

```
cfg_model MODE
```

Looks up the configured model id for a generation mode.

| Parameter | Type | Description |
| --- | --- | --- |
| `MODE` | `string` | The generation mode name. |

Returns: The model id, printed to stdout, or empty if unconfigured.

Source: `lib/config.sh` (lines 173-175)

## `cfg_effort`

*function*

```
cfg_effort MODE
```

Looks up the configured reasoning effort for a generation mode.

| Parameter | Type | Description |
| --- | --- | --- |
| `MODE` | `string` | The generation mode name. |

Returns: The effort level, printed to stdout, or empty if unconfigured.

Source: `lib/config.sh` (lines 177-179)

## `cfg_settings_file`

*function*

```
cfg_settings_file
```

Looks up the configured Claude CLI settings file path.

Returns: The settings file path, printed to stdout, or empty if unconfigured.

Source: `lib/config.sh` (lines 181-183)

## `cfg_all_models`

*function*

```
cfg_all_models
```

Lists every unique model id configured across all modes, including the fallback model.

Returns: Sorted, unique model ids, one per line, printed to stdout.

Source: `lib/config.sh` (lines 186-189)

## `config_style_instructions`

*function*

```
config_style_instructions
```

Renders the voice and style conventions block injected into every system prompt, derived from `voice.style_guide` and `voice.person`, with an optional extra instructions file appended.

Returns: A Markdown fragment with voice and style instructions, printed to stdout.

Source: `lib/config.sh` (lines 193-211)

## `manifest_path`

*function*

```
manifest_path
```

Prints the absolute path to the committed manifest file, `.diataxis/manifest.json`, under the workspace root.

Returns: The manifest file path, printed to stdout.

Source: `lib/manifest.sh` (lines 6)

## `manifest_read`

*function*

```
manifest_read
```

Reads the manifest file, or prints an empty manifest document (`{"version":1,"pages":[]}`) if it does not exist.

Returns: The manifest JSON, printed to stdout.

Source: `lib/manifest.sh` (lines 8-14)

## `manifest_write`

*function*

```
manifest_write JSON
```

Atomically replaces the manifest file by writing to a temporary file in `.diataxis/` and renaming it into place.

| Parameter | Type | Description |
| --- | --- | --- |
| `JSON` | `string` | The full manifest document to write. |

Source: `lib/manifest.sh` (lines 17-22)

## `manifest_get_page`

*function*

```
manifest_get_page SLUG
```

Looks up a page's manifest entry by slug.

| Parameter | Type | Description |
| --- | --- | --- |
| `SLUG` | `string` | The page's slug. |

Returns: The page entry JSON, printed to stdout, or nothing if absent.

Source: `lib/manifest.sh` (lines 25-27)

## `manifest_upsert_page`

*function*

```
manifest_upsert_page ENTRY_JSON
```

Replaces or appends a page's manifest entry by its slug, then keeps the pages array sorted by slug.

| Parameter | Type | Description |
| --- | --- | --- |
| `ENTRY_JSON` | `string` | The page entry JSON, including a `slug` field. |

Source: `lib/manifest.sh` (lines 30-36)

## `manifest_delete_page`

*function*

```
manifest_delete_page SLUG
```

Removes a page's entry from the manifest by slug.

| Parameter | Type | Description |
| --- | --- | --- |
| `SLUG` | `string` | The page's slug. |

Source: `lib/manifest.sh` (lines 39-44)

## `manifest_set_meta`

*function*

```
manifest_set_meta KEY JSON_VALUE
```

Sets a top-level metadata key on the manifest, such as `auth_method` or the workspaces inventory strategy.

| Parameter | Type | Description |
| --- | --- | --- |
| `KEY` | `string` | The top-level manifest key to set. |
| `JSON_VALUE` | `string` | The JSON value to assign. |

Source: `lib/manifest.sh` (lines 48-52)

## `compute_inputs_hash`

*function*

```
compute_inputs_hash MODE SOURCES PLAN_ENTRY_JSON
```

Computes a stable hash covering, in fixed order, the content of every listed source file, the mode's system prompt file, task template, schema, the config's model block, and the plan entry. Any change to these inputs changes the hash, which marks the page stale.

| Parameter | Type | Description |
| --- | --- | --- |
| `MODE` | `string` | One of tutorial, howto, reference, explanation. |
| `SOURCES` | `string` | Newline-separated workspace-relative source file paths. |
| `PLAN_ENTRY_JSON` | `string` | The page's entry in .diataxis/plan.json. |

Returns: The hash, printed to stdout in the form `sha256:<hex>`.

Source: `lib/manifest.sh` (lines 63-81)

## `page_is_stale`

*function*

```
page_is_stale SLUG CURRENT_INPUTS_HASH
```

Determines whether a page needs regeneration by comparing CURRENT_INPUTS_HASH against the hash recorded in the manifest.

| Parameter | Type | Description |
| --- | --- | --- |
| `SLUG` | `string` | The page's slug. |
| `CURRENT_INPUTS_HASH` | `string` | The hash produced by compute_inputs_hash for the current inputs. |

Returns: Exit status 0 (stale, regeneration needed) when the page has no manifest entry or its recorded hash differs; nonzero otherwise.

Source: `lib/manifest.sh` (lines 84-91)

## `page_disk_status`

*function*

```
page_disk_status SLUG ABS_PATH
```

Compares a page's on-disk file against its recorded content hash to detect human edits.

| Parameter | Type | Description |
| --- | --- | --- |
| `SLUG` | `string` | The page's slug. |
| `ABS_PATH` | `path` | Absolute path to the page's file on disk. |

Returns: One of `absent`, `clean`, `edited`, or `unknown`, printed to stdout.

Source: `lib/manifest.sh` (lines 100-116)

## `page_is_frozen`

*function*

```
page_is_frozen SLUG ABS_PATH
```

Determines whether a page must never be regenerated, from either its manifest entry's `frozen` flag or a `frozen: true` key in its file's YAML frontmatter.

| Parameter | Type | Description |
| --- | --- | --- |
| `SLUG` | `string` | The page's slug. |
| `ABS_PATH` | `path` | Absolute path to the page's file on disk. |

Returns: Exit status 0 when frozen, nonzero otherwise.

Source: `lib/manifest.sh` (lines 120-129)

## `budget_remaining`

*function*

```
budget_remaining
```

Computes the USD remaining for the current run by subtracting `$DIATAXIS_RUN_SPENT` from `$DIATAXIS_BUDGET_USD`.

Returns: The remaining budget in USD, printed to stdout, or nothing when no budget is configured (`$DIATAXIS_BUDGET_USD` unset or `null`).

Source: `lib/manifest.sh` (lines 136-141)

## `budget_require`

*function*

```
budget_require [PENDING]
```

Guards against starting new work once the run's budget is exhausted.

| Parameter | Type | Description |
| --- | --- | --- |
| `PENDING` (optional) | `string` | Description of the pending work, used in the error message. Defaults to "remaining work". |

Raises:
- EX_BUDGET when the remaining budget is not greater than zero

Source: `lib/manifest.sh` (lines 145-152)

## `budget_add`

*function*

```
budget_add COST
```

Accumulates a call's cost into `$DIATAXIS_RUN_SPENT`.

| Parameter | Type | Description |
| --- | --- | --- |
| `COST` | `number` | The cost in USD to add. |

Source: `lib/manifest.sh` (lines 155-157)

## `manifest_total_cost`

*function*

```
manifest_total_cost
```

Sums the recorded cost of every page in the manifest.

Returns: The lifetime spend in USD, printed to stdout.

Source: `lib/manifest.sh` (lines 160-162)

## `setup_colors`

*function*

```
setup_colors
```

Sets the `C_RED`, `C_GRN`, `C_YLW` and `C_OFF` ANSI color code variables, or empty strings when `DIATAXIS_NO_COLOR`, `NO_COLOR` is set, or stderr is not a terminal.

Source: `lib/preamble.sh` (lines 32-40)

## `log`

*function*

```
log MESSAGE
```

Writes a message to stderr.

| Parameter | Type | Description |
| --- | --- | --- |
| `MESSAGE` | `string` | The message text. |

Source: `lib/preamble.sh` (lines 42)

## `warn`

*function*

```
warn MESSAGE
```

Writes a message to stderr prefixed with a colored "warning:" label.

| Parameter | Type | Description |
| --- | --- | --- |
| `MESSAGE` | `string` | The message text. |

Source: `lib/preamble.sh` (lines 44)

## `verbose`

*function*

```
verbose MESSAGE
```

Writes a message to stderr only when `$DIATAXIS_VERBOSE` is 1.

| Parameter | Type | Description |
| --- | --- | --- |
| `MESSAGE` | `string` | The message text. |

Source: `lib/preamble.sh` (lines 46-50)

## `die`

*function*

```
die CODE MESSAGE...
```

Writes a colored "error:" message to stderr and exits the process with the given code.

| Parameter | Type | Description |
| --- | --- | --- |
| `CODE` | `integer` | The process exit code. |
| `MESSAGE...` | `string` | The error message text. |

Raises:
- Exits the process with CODE; never returns

Source: `lib/preamble.sh` (lines 52-57)

## `version_ge`

*function*

```
version_ge A B
```

Compares two dot-separated version strings numerically, component by component.

| Parameter | Type | Description |
| --- | --- | --- |
| `A` | `string` | The version to test. |
| `B` | `string` | The version to compare against. |

Returns: Exit status 0 when A is greater than or equal to B, nonzero otherwise.

Source: `lib/preamble.sh` (lines 62-75)

## `sha256_stream`

*function*

```
sha256_stream
```

Hashes stdin with SHA-256, using `sha256sum` if available and falling back to `shasum -a 256`.

Returns: The bare hex digest, printed to stdout.

Source: `lib/preamble.sh` (lines 79-85)

## `sha256_file`

*function*

```
sha256_file PATH
```

Hashes a file's content with SHA-256.

| Parameter | Type | Description |
| --- | --- | --- |
| `PATH` | `path` | The file to hash. |

Returns: The bare hex digest, printed to stdout.

Source: `lib/preamble.sh` (lines 87)

## `b64_decode`

*function*

```
b64_decode
```

Decodes base64 from stdin, probing once whether the installed `base64` takes `-d` (GNU/current macOS) or `-D` (historical BSD) and caching the result in `$DIATAXIS_B64_FLAG`.

Returns: The decoded bytes, printed to stdout.

Source: `lib/preamble.sh` (lines 91-101)

## `sha256_string`

*function*

```
sha256_string STRING
```

Hashes a literal string with SHA-256.

| Parameter | Type | Description |
| --- | --- | --- |
| `STRING` | `string` | The string to hash. |

Returns: The bare hex digest, printed to stdout.

Source: `lib/preamble.sh` (lines 103)

## `iso_now`

*function*

```
iso_now
```

Prints the current UTC time.

Returns: The current time in `YYYY-MM-DDTHH:MM:SSZ` format, printed to stdout.

Source: `lib/preamble.sh` (lines 105)

## `render_template`

*function*

```
render_template FILE
```

Substitutes `${NAME}` occurrences in a file from the environment, envsubst-style, in a single non-recursive pass.

| Parameter | Type | Description |
| --- | --- | --- |
| `FILE` | `path` | The template file to render. |

Returns: The substituted content, printed to stdout.

Source: `lib/preamble.sh` (lines 109-120)

## `awk_float_lt`

*function*

```
awk_float_lt A B
```

Compares two floating point numbers.

| Parameter | Type | Description |
| --- | --- | --- |
| `A` | `number` | The left-hand value. |
| `B` | `number` | The right-hand value. |

Returns: Exit status 0 when A < B, nonzero otherwise.

Source: `lib/preamble.sh` (lines 123)

## `awk_float_sub`

*function*

```
awk_float_sub A B
```

Subtracts one floating point number from another.

| Parameter | Type | Description |
| --- | --- | --- |
| `A` | `number` | The minuend. |
| `B` | `number` | The subtrahend. |

Returns: A minus B, formatted to 4 decimal places, printed to stdout.

Source: `lib/preamble.sh` (lines 126)

## `awk_float_add`

*function*

```
awk_float_add A B
```

Adds two floating point numbers.

| Parameter | Type | Description |
| --- | --- | --- |
| `A` | `number` | The first addend. |
| `B` | `number` | The second addend. |

Returns: A plus B, formatted to 4 decimal places, printed to stdout.

Source: `lib/preamble.sh` (lines 129)

## `doctor_ok`

*function*

```
doctor_ok MESSAGE...
```

Reports a successful doctor check to stderr, only when `$DIATAXIS_DOCTOR_PRINT` is 1.

| Parameter | Type | Description |
| --- | --- | --- |
| `MESSAGE...` | `string` | The success message text. |

Source: `lib/preamble.sh` (lines 135-139)

## `doctor_fail`

*function*

```
doctor_fail CODE MESSAGE...
```

Reports a failed doctor check to stderr and exits with the given code.

| Parameter | Type | Description |
| --- | --- | --- |
| `CODE` | `integer` | The process exit code. |
| `MESSAGE...` | `string` | The failure message text. |

Raises:
- Exits the process with CODE; never returns

Source: `lib/preamble.sh` (lines 141-146)

## `check_claude_on_path`

*function*

```
check_claude_on_path
```

Verifies the `claude` executable is on PATH.

Raises:
- EX_CLAUDE_MISSING when claude is not found on PATH

Source: `lib/preamble.sh` (lines 148-154)

## `check_claude_version`

*function*

```
check_claude_version
```

Parses `claude --version` and verifies it meets `$DIATAXIS_MIN_CLAUDE_VERSION`, exporting `DIATAXIS_CLAUDE_VERSION`.

Raises:
- EX_CLAUDE_OLD when the version cannot be parsed or is older than the minimum

Source: `lib/preamble.sh` (lines 156-168)

## `check_jq`

*function*

```
check_jq
```

Verifies `jq` is on PATH and meets `$DIATAXIS_MIN_JQ_VERSION`.

Raises:
- EX_JQ_MISSING when jq is missing or older than the minimum

Source: `lib/preamble.sh` (lines 170-181)

## `check_git`

*function*

```
check_git
```

Verifies `git` is on PATH and the current directory is inside a git work tree, exporting `DIATAXIS_WORKSPACE` as the tree's top level.

Raises:
- EX_GIT_MISSING when git is missing or the current directory is not inside a git work tree

Source: `lib/preamble.sh` (lines 183-194)

## `claude_auth_status_supported`

*function*

```
claude_auth_status_supported
```

Detects whether the installed `claude` CLI supports the `auth status` subcommand.

Returns: Exit status 0 when supported, nonzero otherwise.

Source: `lib/preamble.sh` (lines 197-199)

## `check_auth`

*function*

```
check_auth
```

Determines the authentication method in effect (`CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, `claude auth status`, or a one-off probe call for older CLIs) and exports `DIATAXIS_AUTH_METHOD`.

Raises:
- EX_UNAUTH when no authentication method succeeds

Source: `lib/preamble.sh` (lines 201-235)

## `check_writable`

*function*

```
check_writable [DOCS_DIR]
```

Verifies the docs directory and `.diataxis/` are writable, or that the workspace root is writable if they do not yet exist.

| Parameter | Type | Description |
| --- | --- | --- |
| `DOCS_DIR` (optional) | `string` | The docs directory, relative to the workspace root. Defaults to "docs". |

Raises:
- EX_UNWRITABLE when the target directory or the workspace root is not writable

Source: `lib/preamble.sh` (lines 237-252)

## `resolve_bare`

*function*

```
resolve_bare [CFG_BARE] [SETTINGS_FILE]
```

Decides whether `--bare` is passed to `claude`, from the detected auth method and the config's `bare` setting, exporting `DIATAXIS_BARE_CAPABLE` and `DIATAXIS_USE_BARE`.

| Parameter | Type | Description |
| --- | --- | --- |
| `CFG_BARE` (optional) | `string` | The config `bare` value: "auto", "true", or "false". Defaults to "auto". |
| `SETTINGS_FILE` (optional) | `string` | Path to a settings file that may carry an apiKeyHelper, trusted to make bare mode capable. |

Raises:
- EX_NOT_BARE_CAPABLE when the config forces "bare": true but the auth method cannot support it

Source: `lib/preamble.sh` (lines 261-294)

## `require_bare_capable`

*function*

```
require_bare_capable
```

Verifies the current auth method is bare-capable, for commands (such as `diataxis check`) that require reproducible CI-equivalent runs.

Raises:
- EX_NOT_BARE_CAPABLE when `$DIATAXIS_BARE_CAPABLE` is not 1

Source: `lib/preamble.sh` (lines 296-301)

## `probe_models`

*function*

```
probe_models MODELS
```

Live-probes each configured model once with a minimal prompt to confirm it is available and permitted. Runs only from `diataxis doctor` when `$DIATAXIS_LIVE` is 1, since it costs money.

| Parameter | Type | Description |
| --- | --- | --- |
| `MODELS` | `string` | Newline-separated unique model ids. |

Raises:
- EX_MODEL_UNAVAILABLE when a model is not available or not permitted for the account

Source: `lib/preamble.sh` (lines 305-322)

## `preamble_run`

*function*

```
preamble_run
```

Runs the fast environment and authentication check sequence (claude on PATH, claude version, jq, git, auth) that executes at the start of every subcommand.

Source: `lib/preamble.sh` (lines 325-331)

## `render_frontmatter`

*function*

```
render_frontmatter SLUG MODE TITLE [VERIFIED]
```

Prints YAML frontmatter for a generated page: title, slug, mode, generator identity, generation timestamp, optional verified flag, and a `frozen: false` default.

| Parameter | Type | Description |
| --- | --- | --- |
| `SLUG` | `string` | The page's slug. |
| `MODE` | `string` | The generation mode. |
| `TITLE` | `string` | The page title. |
| `VERIFIED` (optional) | `string` | "true", "false", or omitted for non-tutorial modes; when non-empty, emitted as the `verified` frontmatter key. |

Returns: The YAML frontmatter block, printed to stdout.

Source: `lib/render.sh` (lines 9-21)

## `render_reference_body`

*function*

```
render_reference_body
```

Reads structured reference-mode JSON from stdin and writes the Markdown body: a title and summary, then one section per symbol with kind, stability, since, signature, description, parameters table, returns, raises, and source citations.

Returns: Markdown, printed to stdout.

Source: `lib/render.sh` (lines 26-51)

## `render_related_jq`

*function*

```
render_related_jq
```

Prints shared jq helper definitions (`uplevels`, `rel_link`) for computing relative links from a page's slug to another page's Markdown file.

Returns: jq source code, printed to stdout.

Source: `lib/render.sh` (lines 55-60)

## `render_howto_body`

*function*

```
render_howto_body SLUG
```

Reads structured how-to-mode JSON from stdin and writes the Markdown body: title, goal, prerequisites, numbered steps with code and expected results, verification, and related links.

| Parameter | Type | Description |
| --- | --- | --- |
| `SLUG` | `string` | The page's slug, used to compute relative related links. |

Returns: Markdown, printed to stdout.

Source: `lib/render.sh` (lines 62-83)

## `render_tutorial_body`

*function*

```
render_tutorial_body SLUG
```

Reads structured tutorial-mode JSON from stdin and writes the Markdown body: title, outcome, time estimate, prerequisites, numbered steps with code, expected output and checkpoints, and next steps.

| Parameter | Type | Description |
| --- | --- | --- |
| `SLUG` | `string` | The page's slug, used to compute relative next-step links. |

Returns: Markdown, printed to stdout.

Source: `lib/render.sh` (lines 85-105)

## `render_explanation_body`

*function*

```
render_explanation_body SLUG
```

Reads structured explanation-mode JSON from stdin and writes the Markdown body: title, thesis, sections, a tradeoffs table, open questions, and related links.

| Parameter | Type | Description |
| --- | --- | --- |
| `SLUG` | `string` | The page's slug, used to compute relative related links. |

Returns: Markdown, printed to stdout.

Source: `lib/render.sh` (lines 107-122)

## `render_page`

*function*

```
render_page MODE SLUG TITLE [VERIFIED]
```

Reads structured JSON from stdin and writes a complete Markdown page (frontmatter plus mode-specific body) by dispatching to the renderer for MODE.

| Parameter | Type | Description |
| --- | --- | --- |
| `MODE` | `string` | One of reference, howto, tutorial, explanation. |
| `SLUG` | `string` | The page's slug. |
| `TITLE` | `string` | The page title. |
| `VERIFIED` (optional) | `string` | Passed through to render_frontmatter. |

Returns: Markdown, printed to stdout.

Raises:
- EX_GENERIC when MODE has no renderer

Source: `lib/render.sh` (lines 125-138)

## `render_audit_findings`

*function*

```
render_audit_findings
```

Reads structured audit findings JSON from stdin and writes a human-readable listing of severity, path, rule, excerpt and suggestion for each finding.

Returns: Plain text, printed to stdout.

Source: `lib/render.sh` (lines 141-149)

