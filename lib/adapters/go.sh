# shellcheck shell=sh
# Go adapter. Contract: adapter_detect, adapter_source_globs,
# adapter_symbol_inventory (NDJSON), adapter_context_files.
# Runs with cwd at the workspace root; emitted paths are workspace-relative.

adapter_detect() { [ -f go.mod ]; }

adapter_source_globs() {
  printf '**/*.go\n'
}

adapter_context_files() {
  for _f in go.mod go.sum Makefile README.md; do
    [ -f "$_f" ] && printf '%s\n' "$_f"
  done
  for _d in .github/workflows docs/adr adr; do
    [ -d "$_d" ] && find "$_d" -type f | LC_ALL=C sort
  done
  return 0
}

# adapter_symbol_inventory: exported declarations with source positions.
# `go doc -all` carries no file/line information, which the citation contract
# needs, so extraction is an awk pass over exported declarations. When the go
# toolchain is present, `go list ./...` validates the module first and the
# strategy is recorded as go-list+grep; otherwise plain grep.
adapter_symbol_inventory() {
  _strategy="grep"
  if command -v go >/dev/null 2>&1 && go list ./... >/dev/null 2>&1; then
    _strategy="go-list+grep"
  fi
  git ls-files '*.go' | grep -v '_test\.go$' | grep -v -E '(^|/)(testdata|vendor)/' \
  | while IFS= read -r _f; do
      awk -v STRATEGY="$_strategy" '
        function jesc(s) {
          gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
          gsub(/\t/, "\\t", s); gsub(/\r/, "", s)
          return s
        }
        /^\/\// {
          d = substr($0, 3)
          sub(/^ /, "", d)
          doc = doc (doc == "" ? "" : "\\n") jesc(d)
          next
        }
        /^(func|type|var|const) [A-Z]/ || /^func \([^)]*\) [A-Z]/ {
          line = $0
          kind = ""
          name = ""
          if (line ~ /^func \(/) {
            kind = "method"
            rest = line
            sub(/^func \([^)]*\)[[:space:]]*/, "", rest)
            split(rest, parts, /[[:space:](]+/)
            name = parts[1]
          } else if (line ~ /^func /) {
            kind = "function"
            split(line, parts, /[[:space:](]+/)
            name = parts[2]
          } else if (line ~ /^type /) {
            split(line, parts, /[[:space:]]+/)
            name = parts[2]
            kind = (line ~ / interface/) ? "interface" : ((line ~ / struct/) ? "struct" : "type")
          } else if (line ~ /^var /) {
            kind = "variable"
            split(line, parts, /[[:space:]=]+/)
            name = parts[2]
          } else if (line ~ /^const /) {
            kind = "constant"
            split(line, parts, /[[:space:]=]+/)
            name = parts[2]
          }
          if (name == "" || name !~ /^[A-Z]/) { doc = ""; next }
          sig = line
          sub(/[[:space:]]*{[[:space:]]*$/, "", sig)
          printf("{\"name\":\"%s\",\"kind\":\"%s\",\"signature\":\"%s\",\"path\":\"%s\",\"line\":%d,\"visibility\":\"public\",\"doc_comment\":\"%s\",\"strategy\":\"%s\"}\n",
            jesc(name), kind, jesc(sig), jesc(FILENAME), FNR, doc, STRATEGY)
          doc = ""
          next
        }
        { doc = "" }
      ' "$_f"
    done
}
