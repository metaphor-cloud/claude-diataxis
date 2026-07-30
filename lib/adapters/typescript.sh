# shellcheck shell=sh
# TypeScript adapter. Contract: adapter_detect, adapter_source_globs,
# adapter_symbol_inventory (NDJSON), adapter_context_files.
# Runs with cwd at the workspace root; emitted paths are workspace-relative.

adapter_detect() { [ -f package.json ] && [ -f tsconfig.json ]; }

adapter_source_globs() {
  printf 'src/**/*.ts\n'
  printf 'src/**/*.tsx\n'
  printf '**/*.d.ts\n'
}

adapter_context_files() {
  for _f in package.json tsconfig.json package-lock.json pnpm-lock.yaml yarn.lock README.md; do
    [ -f "$_f" ] && printf '%s\n' "$_f"
  done
  for _d in .github/workflows docs/adr adr; do
    [ -d "$_d" ] && find "$_d" -type f | LC_ALL=C sort
  done
  return 0
}

# adapter_symbol_inventory:
#   1. typedoc --json when typedoc is on PATH and succeeds
#   2. else a grep pass over exported declarations in .ts/.tsx/.d.ts files
adapter_symbol_inventory() {
  if command -v typedoc >/dev/null 2>&1; then
    if _ts_inventory_typedoc; then
      return 0
    fi
  fi
  _ts_inventory_grep
}

_ts_inventory_typedoc() {
  _tmp=$(mktemp "${TMPDIR:-/tmp}/diataxis-typedoc.XXXXXX")
  if ! typedoc --json "$_tmp" >/dev/null 2>&1; then
    rm -f "$_tmp"
    return 1
  fi
  # typedoc kind codes: 32 variable, 64 function, 128 class, 256 interface,
  # 2097152 type alias, 4194304 reference, 8 enum.
  if ! jq -c '
    [recurse(.children[]?)]
    | .[]
    | select(.sources and .name)
    | select(.kind == 32 or .kind == 64 or .kind == 128 or .kind == 256 or .kind == 8 or .kind == 2097152)
    | {
        name: .name,
        kind: (if .kind == 64 then "function"
               elif .kind == 128 then "class"
               elif .kind == 256 then "interface"
               elif .kind == 32 then "variable"
               elif .kind == 8 then "type"
               else "type" end),
        signature: .name,
        path: .sources[0].fileName,
        line: .sources[0].line,
        visibility: "public",
        doc_comment: ((.comment.summary // []) | map(.text // "") | join("")),
        strategy: "typedoc"
      }' "$_tmp" 2>/dev/null; then
    rm -f "$_tmp"
    return 1
  fi
  rm -f "$_tmp"
  return 0
}

_ts_source_files() {
  git ls-files '*.ts' '*.tsx' \
    | grep -v -E '(^|/)(node_modules|dist|build|coverage)/' \
    | grep -v -E '\.(test|spec)\.tsx?$'
}

_ts_inventory_grep() {
  _ts_source_files | while IFS= read -r _f; do
    awk '
      function jesc(s) {
        gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
        gsub(/\t/, "\\t", s); gsub(/\r/, "", s)
        return s
      }
      /^[[:space:]]*\/\/\// || /^[[:space:]]*\*/ {
        d = $0
        sub(/^[[:space:]]*(\/\/\/|\*+\/?)[[:space:]]?/, "", d)
        if (d !~ /^\/\*/ && d != "") doc = doc (doc == "" ? "" : "\\n") jesc(d)
        next
      }
      /^export (default )?(async )?(abstract )?(function|const|let|var|class|interface|type|enum)[[:space:]]/ {
        line = $0
        tmp = line
        sub(/^export (default )?(async )?(abstract )?/, "", tmp)
        split(tmp, w, /[[:space:]]+/)
        kw = w[1]
        kind = "variable"
        if (kw == "function") kind = "function"
        else if (kw == "class") kind = "class"
        else if (kw == "interface") kind = "interface"
        else if (kw == "type" || kw == "enum") kind = "type"
        else if (kw == "const" || kw == "let" || kw == "var") kind = "variable"
        rest = tmp
        sub(/^[a-z]+[[:space:]]+/, "", rest)
        split(rest, parts, /[[:space:]<(=:;{]+/)
        name = parts[1]
        if (name == "") { doc = ""; next }
        sig = line
        sub(/[[:space:]]*[{=][^{=]*$/, "", sig)
        printf("{\"name\":\"%s\",\"kind\":\"%s\",\"signature\":\"%s\",\"path\":\"%s\",\"line\":%d,\"visibility\":\"public\",\"doc_comment\":\"%s\",\"strategy\":\"grep\"}\n",
          jesc(name), kind, jesc(sig), jesc(FILENAME), FNR, doc, "grep")
        doc = ""
        next
      }
      /^[[:space:]]*$/ { next }
      { doc = "" }
    ' "$_f"
  done
}
