# shellcheck shell=sh
# Rust adapter. Contract: adapter_detect, adapter_source_globs,
# adapter_symbol_inventory (NDJSON), adapter_context_files.
# Runs with cwd at the workspace root; emitted paths are workspace-relative.

adapter_detect() { [ -f Cargo.toml ]; }

adapter_source_globs() {
  printf 'src/**/*.rs\n'
  printf '**/src/**/*.rs\n'
}

adapter_context_files() {
  for _f in Cargo.toml Cargo.lock rust-toolchain.toml README.md; do
    [ -f "$_f" ] && printf '%s\n' "$_f"
  done
  for _d in .github/workflows docs/adr adr; do
    [ -d "$_d" ] && find "$_d" -type f | LC_ALL=C sort
  done
  return 0
}

# adapter_symbol_inventory:
#   1. cargo +nightly rustdoc JSON when a nightly toolchain is available
#   2. else a grep pass over pub items (cargo metadata confirms the crate)
# Every record carries the strategy so downstream consumers know a
# grep-derived inventory is lower confidence.
adapter_symbol_inventory() {
  if command -v cargo >/dev/null 2>&1 && cargo +nightly --version >/dev/null 2>&1; then
    if _rust_inventory_rustdoc; then
      return 0
    fi
  fi
  _rust_inventory_grep
}

_rust_inventory_rustdoc() {
  _tmp=$(mktemp -d "${TMPDIR:-/tmp}/diataxis-rustdoc.XXXXXX")
  if ! cargo +nightly rustdoc --target-dir "$_tmp" -- -Zunstable-options \
      --output-format json >/dev/null 2>&1; then
    rm -rf "$_tmp"
    return 1
  fi
  _json=$(find "$_tmp/doc" -name '*.json' 2>/dev/null | head -1)
  if [ -z "$_json" ]; then
    rm -rf "$_tmp"
    return 1
  fi
  # Best-effort mapping of the rustdoc JSON index; the format is unstable, so
  # any surprise falls back to grep.
  if ! jq -c '
    .index | to_entries[] | .value
    | select(.name != null and .span != null and .visibility == "public")
    | (.inner | if type == "object" then keys[0] else "other" end) as $k
    | select($k as $x | ["function", "struct", "enum", "trait", "constant", "static", "module", "type_alias"] | index($x))
    | {
        name: .name,
        kind: ({function: "function", struct: "struct", enum: "type",
                trait: "interface", constant: "constant", static: "variable",
                module: "module", type_alias: "type"}[$k] // "type"),
        signature: .name,
        path: .span.filename,
        line: .span.begin[0],
        visibility: "public",
        doc_comment: (.docs // ""),
        strategy: "rustdoc-json"
      }' "$_json" 2>/dev/null; then
    rm -rf "$_tmp"
    return 1
  fi
  rm -rf "$_tmp"
  return 0
}

_rust_inventory_grep() {
  _strategy="grep"
  if command -v cargo >/dev/null 2>&1 \
      && cargo metadata --no-deps --format-version 1 >/dev/null 2>&1; then
    _strategy="cargo-metadata+grep"
  fi
  git ls-files '*.rs' | grep -v -E '(^|/)(tests|benches|examples)/' \
  | while IFS= read -r _f; do
      awk -v STRATEGY="$_strategy" '
        function jesc(s) {
          gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
          gsub(/\t/, "\\t", s); gsub(/\r/, "", s)
          return s
        }
        /^[[:space:]]*\/\/\// {
          d = substr($0, index($0, "///") + 3)
          sub(/^ /, "", d)
          doc = doc (doc == "" ? "" : "\\n") jesc(d)
          next
        }
        /^[[:space:]]*pub[[:space:](]/ {
          line = $0
          sub(/^[[:space:]]+/, "", line)
          vis = "public"
          if (line ~ /^pub\(/) vis = "crate"
          decl = line
          sub(/^pub(\([^)]*\))?[[:space:]]+/, "", decl)
          tmp = decl
          # Strip fn modifiers; const only when it modifies fn, else
          # `pub const NAME` would lose its keyword before kind detection.
          sub(/^(async |unsafe |extern "[^"]*" )+/, "", tmp)
          if (tmp ~ /^const fn /) sub(/^const /, "", tmp)
          n = split(tmp, parts, /[[:space:]<(:;={]+/)
          kw = (n >= 1) ? parts[1] : ""
          name = (n >= 2) ? parts[2] : ""
          kind = ""
          if (kw == "fn") kind = "function"
          else if (kw == "struct") kind = "struct"
          else if (kw == "enum") kind = "type"
          else if (kw == "trait") kind = "interface"
          else if (kw == "type") kind = "type"
          else if (kw == "const") kind = "constant"
          else if (kw == "static") kind = "variable"
          else if (kw == "mod") kind = "module"
          if (kind == "" || name == "") { doc = ""; next }
          sig = line
          sub(/[[:space:]]*[{;][[:space:]]*$/, "", sig)
          printf("{\"name\":\"%s\",\"kind\":\"%s\",\"signature\":\"%s\",\"path\":\"%s\",\"line\":%d,\"visibility\":\"%s\",\"doc_comment\":\"%s\",\"strategy\":\"%s\"}\n",
            jesc(name), kind, jesc(sig), jesc(FILENAME), FNR, vis, doc, STRATEGY)
          doc = ""
          next
        }
        { doc = "" }
      ' "$_f"
    done
}
