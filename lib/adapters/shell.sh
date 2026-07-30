# shellcheck shell=sh
# Shell adapter. Contract: adapter_detect, adapter_source_globs,
# adapter_symbol_inventory (NDJSON), adapter_context_files.
# Runs with cwd at the workspace root; emitted paths are workspace-relative.
#
# Detection is deliberately last in the auto-detect order: most repositories
# contain some shell, so this adapter only claims a workspace no other
# adapter recognises. There is no native symbol tooling for shell; the
# inventory is always an awk pass over function definitions and top-level
# constants, and the strategy is recorded as grep. Convention: names with a
# leading underscore are internal.

adapter_detect() {
  if git ls-files -- '*.sh' '*.bash' 2>/dev/null | head -1 | grep -q .; then
    return 0
  fi
  # Extensionless scripts: a tracked file under bin/ with a shell shebang.
  git ls-files -- 'bin/*' 2>/dev/null | while IFS= read -r _f; do
    if [ -f "$_f" ] \
        && head -1 "$_f" 2>/dev/null | grep -Eq '^#!.*/(env[[:space:]]+)?(sh|bash|dash|ksh)([[:space:]]|$)'; then
      printf 'hit\n'
    fi
  done | grep -q .
}

adapter_source_globs() {
  printf '**/*.sh\n'
  printf '**/*.bash\n'
  printf 'bin/**\n'
}

adapter_context_files() {
  for _f in Makefile justfile install.sh .shellcheckrc README.md; do
    [ -f "$_f" ] && printf '%s\n' "$_f"
  done
  for _d in .github/workflows docs/adr adr; do
    [ -d "$_d" ] && find "$_d" -type f | LC_ALL=C sort
  done
  return 0
}

# _shell_source_files: tracked .sh/.bash files plus extensionless scripts
# with a shell shebang, minus test suites.
_shell_source_files() {
  {
    git ls-files -- '*.sh' '*.bash' 2>/dev/null
    git ls-files 2>/dev/null | while IFS= read -r _f; do
      case "$_f" in
        *.sh|*.bash) continue ;;
      esac
      [ -f "$_f" ] || continue
      head -1 "$_f" 2>/dev/null \
        | grep -Eq '^#!.*/(env[[:space:]]+)?(sh|bash|dash|ksh)([[:space:]]|$)' \
        && printf '%s\n' "$_f"
    done
  } | grep -v -E '\.bats$' | grep -v -E '(^|/)tests?/' | LC_ALL=C sort -u
}

adapter_symbol_inventory() {
  _shell_source_files | while IFS= read -r _f; do
    awk '
      function jesc(s) {
        gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
        gsub(/\t/, "\\t", s); gsub(/\r/, "", s)
        return s
      }
      function emit(name, kind, sig, vis) {
        printf("{\"name\":\"%s\",\"kind\":\"%s\",\"signature\":\"%s\",\"path\":\"%s\",\"line\":%d,\"visibility\":\"%s\",\"doc_comment\":\"%s\",\"strategy\":\"grep\"}\n",
          jesc(name), kind, jesc(sig), jesc(FILENAME), FNR, vis, doc)
        doc = ""
      }
      NR == 1 && /^#!/ { next }
      /^[[:space:]]*#/ {
        d = $0
        sub(/^[[:space:]]*#+[[:space:]]?/, "", d)
        if (d ~ /^shellcheck/) next
        doc = doc (doc == "" ? "" : "\\n") jesc(d)
        next
      }
      # POSIX and bash function definitions: name() {, function name {,
      # function name() {, and subshell bodies name() (.
      /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*[{(]?[[:space:]]*$/ \
      || /^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\{?[[:space:]]*$/ {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        name = line
        sub(/^function[[:space:]]+/, "", name)
        sub(/[[:space:]]*\(\).*$/, "", name)
        sub(/[[:space:]]*\{.*$/, "", name)
        if (name == "" || name !~ /^[A-Za-z_][A-Za-z0-9_]*$/) { doc = ""; next }
        vis = (name ~ /^_/) ? "internal" : "public"
        emit(name, "function", name "()", vis)
        next
      }
      # Top-level UPPER_CASE constants (column 0 only).
      /^[A-Z][A-Z0-9_]*=/ {
        line = $0
        name = line
        sub(/=.*$/, "", name)
        sig = line
        sub(/[[:space:]]*#.*$/, "", sig)
        emit(name, "constant", sig, "public")
        next
      }
      { doc = "" }
    ' "$_f"
  done
}
