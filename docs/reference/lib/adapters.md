---
title: "lib/adapters reference"
slug: reference/lib/adapters
mode: reference
generated_by: diataxis
generated_at: 2026-07-29T21:43:03Z
frozen: false
---

# lib/adapters reference

Function-level reference for the five language adapters (Go, Python, Rust, shell, TypeScript), each implementing the same adapter_detect/adapter_source_globs/adapter_symbol_inventory/adapter_context_files contract.

## `adapter_detect (go.sh)`

*function*

```
adapter_detect()
```

Returns success if a go.mod file exists at the workspace root, identifying the workspace as a Go module.

Returns: Shell exit status 0 if go.mod exists, non-zero otherwise.

Source: `lib/adapters/go.sh` (lines 6-6)

## `adapter_source_globs (go.sh)`

*function*

```
adapter_source_globs()
```

Prints the glob pattern used to locate Go source files.

Returns: Newline-terminated glob pattern written to stdout: **/*.go.

Source: `lib/adapters/go.sh` (lines 8-10)

## `adapter_context_files (go.sh)`

*function*

```
adapter_context_files()
```

Prints workspace-relative paths of Go build and project metadata files, plus any files under .github/workflows, docs/adr, or adr, for use as generation context.

Returns: Newline-terminated list of existing paths from go.mod, go.sum, Makefile, README.md, and the discovered directories; exit status 0.

Source: `lib/adapters/go.sh` (lines 12-20)

## `adapter_symbol_inventory (go.sh)`

*function*

```
adapter_symbol_inventory()
```

Emits an NDJSON symbol inventory of exported Go declarations (functions, methods, types, vars, consts) by running an awk pass over tracked non-test, non-vendor, non-testdata .go files. Records strategy as go-list+grep when the go toolchain is present and go list ./... succeeds, otherwise grep.

Returns: NDJSON records on stdout, one per exported declaration, each with name, kind, signature, path, line, visibility, doc_comment, and strategy fields.

Source: `lib/adapters/go.sh` (lines 27-84)

## `adapter_detect (python.sh)`

*function*

```
adapter_detect()
```

Returns success if pyproject.toml or setup.py exists at the workspace root, identifying the workspace as a Python project.

Returns: Shell exit status 0 if either file exists, non-zero otherwise.

Source: `lib/adapters/python.sh` (lines 6-6)

## `adapter_source_globs (python.sh)`

*function*

```
adapter_source_globs()
```

Prints glob patterns used to locate Python source files, preferring an src/ layout.

Returns: Newline-terminated glob patterns written to stdout: src/**/*.py and **/*.py.

Source: `lib/adapters/python.sh` (lines 8-11)

## `adapter_context_files (python.sh)`

*function*

```
adapter_context_files()
```

Prints workspace-relative paths of Python packaging and project metadata files, plus any files under .github/workflows, docs/adr, or adr, for use as generation context.

Returns: Newline-terminated list of existing paths from pyproject.toml, setup.py, setup.cfg, requirements.txt, README.md, and the discovered directories; exit status 0.

Source: `lib/adapters/python.sh` (lines 13-21)

## `_python_interpreter`

*function*

```
_python_interpreter()
```

Prints the name of the available Python interpreter binary, preferring python3 over python.

Returns: python3 or python on stdout; prints nothing if neither is on PATH.

Source: `lib/adapters/python.sh` (lines 23-29)

## `_python_source_files`

*function*

```
_python_source_files()
```

Lists tracked .py files, excluding test directories (tests, testdata), virtual environments (.venv, venv), node_modules, and test-named files (conftest.py, test_*.py, *_test.py).

Returns: Newline-terminated list of workspace-relative Python source file paths.

Source: `lib/adapters/python.sh` (lines 31-35)

## `adapter_symbol_inventory (python.sh)`

*function*

```
adapter_symbol_inventory()
```

Emits an NDJSON symbol inventory of Python declarations, trying strategies in order: griffe dump when the griffe package is importable, then the bundled python_ast.py AST script under any available interpreter, then a grep pass over def/class lines.

Returns: Shell exit status 0 with NDJSON records on stdout produced by the first strategy that succeeds.

Source: `lib/adapters/python.sh` (lines 41-55)

## `_python_packages`

*function*

```
_python_packages()
```

Lists top-level importable package names, checked under src/ first and then the workspace root, identified by the presence of __init__.py.

Returns: Sorted, deduplicated newline-terminated list of package directory names.

Source: `lib/adapters/python.sh` (lines 59-64)

## `_python_inventory_griffe`

*function*

```
_python_inventory_griffe(_py)
```

Runs griffe dump for each package returned by _python_packages, transforming the JSON dump into NDJSON symbol records for functions, classes, and attributes (reported as variable) via a jq walk that recurses into class and module members. Visibility is internal for names starting with an underscore.

| Parameter | Type | Description |
| --- | --- | --- |
| `_py` | `string` | Name of the Python interpreter binary to invoke (from _python_interpreter). |

Returns: Shell exit status: 0 if at least one package dump succeeded, 1 if no package produced a dump; NDJSON records with strategy "griffe" are printed to stdout as a side effect.

Source: `lib/adapters/python.sh` (lines 66-91)

## `_python_inventory_grep`

*function*

```
_python_inventory_grep()
```

Falls back to an awk pass over def/async def/class lines in each file from _python_source_files, emitting one NDJSON record per declaration with strategy grep and empty doc_comment.

Returns: NDJSON records on stdout, one per function or class declaration.

Source: `lib/adapters/python.sh` (lines 93-118)

## `adapter_detect (rust.sh)`

*function*

```
adapter_detect()
```

Returns success if a Cargo.toml file exists at the workspace root, identifying the workspace as a Rust crate.

Returns: Shell exit status 0 if Cargo.toml exists, non-zero otherwise.

Source: `lib/adapters/rust.sh` (lines 6-6)

## `adapter_source_globs (rust.sh)`

*function*

```
adapter_source_globs()
```

Prints glob patterns used to locate Rust source files, covering both a top-level src/ directory and nested crate src/ directories in a workspace.

Returns: Newline-terminated glob patterns written to stdout: src/**/*.rs and **/src/**/*.rs.

Source: `lib/adapters/rust.sh` (lines 8-11)

## `adapter_context_files (rust.sh)`

*function*

```
adapter_context_files()
```

Prints workspace-relative paths of Rust build and project metadata files, plus any files under .github/workflows, docs/adr, or adr, for use as generation context.

Returns: Newline-terminated list of existing paths from Cargo.toml, Cargo.lock, rust-toolchain.toml, README.md, and the discovered directories; exit status 0.

Source: `lib/adapters/rust.sh` (lines 13-21)

## `adapter_symbol_inventory (rust.sh)`

*function*

```
adapter_symbol_inventory()
```

Emits an NDJSON symbol inventory of public Rust items, trying cargo +nightly rustdoc JSON output first when a nightly toolchain is available, and falling back to a grep pass over pub declarations.

Returns: Shell exit status 0 with NDJSON records on stdout produced by the first strategy that succeeds.

Source: `lib/adapters/rust.sh` (lines 28-35)

## `_rust_inventory_rustdoc`

*function*

```
_rust_inventory_rustdoc()
```

Runs cargo +nightly rustdoc with unstable JSON output into a temporary target directory, then maps the resulting rustdoc JSON index (functions, structs, enums, traits, constants, statics, modules, type aliases with public visibility) to NDJSON symbol records via jq, recording strategy rustdoc-json. Cleans up the temporary directory before returning.

Returns: Shell exit status 0 with NDJSON records on stdout if the rustdoc build and jq mapping succeed; 1 if the build fails, no JSON file is produced, or the jq mapping fails.

Source: `lib/adapters/rust.sh` (lines 37-73)

## `_rust_inventory_grep`

*function*

```
_rust_inventory_grep()
```

Falls back to an awk pass over pub-prefixed declarations in tracked .rs files (excluding tests, benches, examples directories), classifying fn/struct/enum/trait/type/const/static/mod keywords into symbol kinds and capturing preceding /// doc comments. Visibility is crate for pub(...) restricted items and public otherwise. Records strategy as cargo-metadata+grep when cargo metadata succeeds, otherwise grep.

Returns: NDJSON records on stdout, one per public declaration.

Source: `lib/adapters/rust.sh` (lines 75-130)

## `adapter_detect (shell.sh)`

*function*

```
adapter_detect()
```

Returns success if the workspace has any tracked *.sh or *.bash file, or a tracked file under bin/ whose first line is a shell shebang (sh, bash, dash, or ksh, optionally via env). Intended to run last in adapter auto-detection since most repositories contain some shell.

Returns: Shell exit status 0 if a shell script is found by either check, non-zero otherwise.

Source: `lib/adapters/shell.sh` (lines 13-24)

## `adapter_source_globs (shell.sh)`

*function*

```
adapter_source_globs()
```

Prints glob patterns used to locate shell source files, including extensionless scripts under bin/.

Returns: Newline-terminated glob patterns written to stdout: **/*.sh, **/*.bash, and bin/**.

Source: `lib/adapters/shell.sh` (lines 26-30)

## `adapter_context_files (shell.sh)`

*function*

```
adapter_context_files()
```

Prints workspace-relative paths of shell build and project metadata files, plus any files under .github/workflows, docs/adr, or adr, for use as generation context.

Returns: Newline-terminated list of existing paths from Makefile, justfile, install.sh, .shellcheckrc, README.md, and the discovered directories; exit status 0.

Source: `lib/adapters/shell.sh` (lines 32-40)

## `_shell_source_files`

*function*

```
_shell_source_files()
```

Lists tracked .sh/.bash files plus other tracked files whose first line is a shell shebang, excluding .bats files and files under tests/ or test/ directories.

Returns: Sorted, deduplicated newline-terminated list of workspace-relative shell source file paths.

Source: `lib/adapters/shell.sh` (lines 44-57)

## `adapter_symbol_inventory (shell.sh)`

*function*

```
adapter_symbol_inventory()
```

Emits an NDJSON symbol inventory of shell function definitions and top-level UPPER_CASE constant assignments by running an awk pass over each file from _shell_source_files. There is no native symbol tooling for shell, so the strategy is always recorded as grep. Names with a leading underscore are marked internal; all others are public.

Returns: NDJSON records on stdout, one per function or constant, each with name, kind, signature, path, line, visibility, doc_comment, and strategy fields.

Source: `lib/adapters/shell.sh` (lines 59-108)

## `adapter_detect (typescript.sh)`

*function*

```
adapter_detect()
```

Returns success if both package.json and tsconfig.json exist at the workspace root, identifying the workspace as a TypeScript project.

Returns: Shell exit status 0 if both files exist, non-zero otherwise.

Source: `lib/adapters/typescript.sh` (lines 6-6)

## `adapter_source_globs (typescript.sh)`

*function*

```
adapter_source_globs()
```

Prints glob patterns used to locate TypeScript source files under an src/ layout, including declaration files anywhere in the workspace.

Returns: Newline-terminated glob patterns written to stdout: src/**/*.ts, src/**/*.tsx, and **/*.d.ts.

Source: `lib/adapters/typescript.sh` (lines 8-12)

## `adapter_context_files (typescript.sh)`

*function*

```
adapter_context_files()
```

Prints workspace-relative paths of TypeScript/Node package and project metadata files, plus any files under .github/workflows, docs/adr, or adr, for use as generation context.

Returns: Newline-terminated list of existing paths from package.json, tsconfig.json, package-lock.json, pnpm-lock.yaml, yarn.lock, README.md, and the discovered directories; exit status 0.

Source: `lib/adapters/typescript.sh` (lines 14-22)

## `adapter_symbol_inventory (typescript.sh)`

*function*

```
adapter_symbol_inventory()
```

Emits an NDJSON symbol inventory of TypeScript declarations, using typedoc --json when the typedoc binary is on PATH and succeeds, otherwise falling back to a grep pass over exported declarations.

Returns: Shell exit status 0 with NDJSON records on stdout produced by the first strategy that succeeds.

Source: `lib/adapters/typescript.sh` (lines 27-34)

## `_ts_inventory_typedoc`

*function*

```
_ts_inventory_typedoc()
```

Runs typedoc --json into a temporary file, then maps the resulting node tree (recursing into children) to NDJSON symbol records via jq for typedoc kind codes 32 (variable), 64 (function), 128 (class), 256 (interface), 8 (enum, reported as type), and 2097152 (type alias, reported as type), recording strategy typedoc. Removes the temporary file before returning.

Returns: Shell exit status 0 with NDJSON records on stdout if typedoc and the jq mapping succeed; 1 if typedoc fails or the jq mapping fails.

Source: `lib/adapters/typescript.sh` (lines 36-69)

## `_ts_source_files`

*function*

```
_ts_source_files()
```

Lists tracked .ts and .tsx files, excluding node_modules, dist, build, and coverage directories, and .test./.spec. files.

Returns: Newline-terminated list of workspace-relative TypeScript source file paths.

Source: `lib/adapters/typescript.sh` (lines 71-75)

## `_ts_inventory_grep`

*function*

```
_ts_inventory_grep()
```

Falls back to an awk pass over export-prefixed declarations (function, const, let, var, class, interface, type, enum, including default/async/abstract modifiers) in each file from _ts_source_files, capturing preceding /// or block-comment lines as doc_comment and recording strategy grep. All emitted symbols are marked public.

Returns: NDJSON records on stdout, one per exported declaration.

Source: `lib/adapters/typescript.sh` (lines 77-119)

