# shellcheck shell=sh
# Python adapter. Contract: adapter_detect, adapter_source_globs,
# adapter_symbol_inventory (NDJSON), adapter_context_files.
# Runs with cwd at the workspace root; emitted paths are workspace-relative.

adapter_detect() { [ -f pyproject.toml ] || [ -f setup.py ]; }

adapter_source_globs() {
  printf 'src/**/*.py\n'
  printf '**/*.py\n'
}

adapter_context_files() {
  for _f in pyproject.toml setup.py setup.cfg requirements.txt README.md; do
    [ -f "$_f" ] && printf '%s\n' "$_f"
  done
  for _d in .github/workflows docs/adr adr; do
    [ -d "$_d" ] && find "$_d" -type f | LC_ALL=C sort
  done
  return 0
}

_python_interpreter() {
  if command -v python3 >/dev/null 2>&1; then
    printf 'python3\n'
  elif command -v python >/dev/null 2>&1; then
    printf 'python\n'
  fi
}

_python_source_files() {
  git ls-files '*.py' \
    | grep -v -E '(^|/)(tests?|testdata|\.venv|venv|node_modules)/' \
    | grep -v -E '(^|/)(conftest|test_[^/]*|[^/]*_test)\.py$'
}

# adapter_symbol_inventory:
#   1. griffe dump when installed (module-level API model, respects __all__)
#   2. else the ast script shipped with the harness, via any python
#   3. else a grep pass over def/class lines
adapter_symbol_inventory() {
  _py=$(_python_interpreter)
  if [ -n "$_py" ] && "$_py" -c 'import griffe' >/dev/null 2>&1; then
    if _python_inventory_griffe "$_py"; then
      return 0
    fi
  fi
  if [ -n "$_py" ]; then
    # shellcheck disable=SC2046 # file list word splitting is intended
    _python_source_files | tr '\n' '\0' \
      | xargs -0 "$_py" "$DIATAXIS_ROOT/lib/adapters/python_ast.py" 2>/dev/null \
      && return 0
  fi
  _python_inventory_grep
}

# _python_packages: top-level importable packages (dirs with __init__.py),
# looking under src/ first.
_python_packages() {
  for _d in src/*/ ./*/; do
    [ -f "${_d}__init__.py" ] || continue
    basename "$_d"
  done | sort -u
}

_python_inventory_griffe() {
  _py=$1
  _found=1
  for _pkg in $(_python_packages); do
    _dump=$("$_py" -m griffe dump "$_pkg" 2>/dev/null) || continue
    _found=0
    printf '%s' "$_dump" | jq -c '
      def walk_members:
        (.members // {} | to_entries[] | .value) as $m
        | ($m
           | select(.kind == "function" or .kind == "class" or .kind == "attribute")
           | {
               name: .name,
               kind: (if .kind == "attribute" then "variable" else .kind end),
               signature: (.name),
               path: (.filepath // ""),
               line: (.lineno // 0),
               visibility: (if (.name | startswith("_")) then "internal" else "public" end),
               doc_comment: (.docstring.value // ""),
               strategy: "griffe"
             }),
          ($m | select(.kind == "class" or .kind == "module") | walk_members);
      to_entries[] | .value | walk_members' 2>/dev/null || return 1
  done
  return $_found
}

_python_inventory_grep() {
  _python_source_files | while IFS= read -r _f; do
    awk '
      function jesc(s) {
        gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
        gsub(/\t/, "\\t", s); gsub(/\r/, "", s)
        return s
      }
      /^(def|async def|class) [A-Za-z_]/ {
        line = $0
        kind = (line ~ /^class /) ? "class" : "function"
        tmp = line
        sub(/^(async )?def /, "", tmp)
        sub(/^class /, "", tmp)
        split(tmp, parts, /[[:space:](:]+/)
        name = parts[1]
        if (name == "") next
        vis = (name ~ /^_/) ? "internal" : "public"
        sig = line
        sub(/:[[:space:]]*$/, "", sig)
        printf("{\"name\":\"%s\",\"kind\":\"%s\",\"signature\":\"%s\",\"path\":\"%s\",\"line\":%d,\"visibility\":\"%s\",\"doc_comment\":\"\",\"strategy\":\"grep\"}\n",
          jesc(name), kind, jesc(sig), jesc(FILENAME), FNR, vis)
      }
    ' "$_f"
  done
}
