---
title: "Write a language adapter"
slug: tutorials/write-a-language-adapter
mode: tutorial
generated_by: diataxis
generated_at: 2026-07-29T21:28:05Z
verified: true
frozen: false
---

# Write a language adapter

In this tutorial you will build: You build a Lua language adapter that implements all four contract functions, run it against a fixture repository you create, and get two golden comparisons passing: the symbol inventory it emits, and the reference pages the harness derives from that inventory. At the end you have a working `lua.sh` adapter and a fixture repository ready to drop into a claude-diataxis checkout.

Time: about 30 minutes.

## What you need

- git. Check it with `git --version`; any version from 2.20 works.
- jq. Check it with `jq --version`; any version from 1.6 works.
- A POSIX shell and awk, which macOS and every Linux distribution ship by default. Check them with `sh -c 'awk --version || awk -W version'`.
- An empty directory to work in. Every command in steps 1 to 7 runs there and nowhere else.
- A claude-diataxis checkout, needed only for the final step. Steps 1 to 7 need nothing but the tools above.

## Step 1: Build the fixture repository your adapter will read. An adapter never sees a filesystem directly: it runs with the working directory at a workspace root and asks git which files are tracked, so the fixture has to be a real git repository with a commit. This one carries a Lua module, a command line script, a spec file that must stay out of the inventory, and the marker files an adapter uses for detection and context.

```sh
mkdir -p fixture/src fixture/bin fixture/spec adapters

cat > fixture/keys.rockspec <<'EOF'
package = "keys"
version = "1.0-1"
EOF

cat > fixture/README.md <<'EOF'
# keys

Signing key rotation for Lua services.
EOF

cat > fixture/.luacheckrc <<'EOF'
std = "lua54"
EOF

cat > fixture/src/keys.lua <<'EOF'
-- Key rotation helpers for the keys module.
local M = {}

KEY_ROTATION_LIMIT = 5

-- Rotate the signing key identified by id.
function M.rotate_key(id)
  if not id then return nil end
  return true
end

-- Internal helper, not part of the public surface.
local function check_id(id)
  return id ~= nil
end

return M
EOF

cat > fixture/bin/keytool.lua <<'EOF'
-- Command line entrypoint for key management.
local keys = require("keys")

-- Print usage and exit.
function usage()
  print("usage: keytool rotate <id>")
end

usage()
EOF

cat > fixture/spec/keys_spec.lua <<'EOF'
-- A spec file: the inventory must leave it out.
function test_rotate_key()
  return true
end
EOF

(cd fixture \
  && git init -q \
  && git add -A \
  && git -c user.email=you@example.com -c user.name=you commit -q -m "fixture")

(cd fixture && git ls-files)
```

You should see:

```
.luacheckrc
README.md
bin/keytool.lua
keys.rockspec
spec/keys_spec.lua
src/keys.lua
```

Checkpoint: You have a `fixture/` git repository with six tracked files, and an empty `adapters/` directory next to it. Git may also print a hint about the default branch name; that goes to standard error and does not affect anything here.

## Step 2: Write the first half of the adapter. `adapter_detect` returns success when the workspace belongs to this language, and prints nothing; the Go adapter is a single `[ -f go.mod ]` test for exactly this reason. `adapter_source_globs` prints the patterns that make a file documentable, one per line. Both run with the working directory already at the workspace root, so every path is workspace-relative.

```sh
cat > adapters/lua.sh <<'EOF'
# shellcheck shell=sh
# Lua adapter. Contract: adapter_detect, adapter_source_globs,
# adapter_symbol_inventory (NDJSON), adapter_context_files.
# Runs with cwd at the workspace root; emitted paths are workspace-relative.

adapter_detect() {
  git ls-files -- '*.rockspec' 2>/dev/null | head -1 | grep -q .
}

adapter_source_globs() {
  printf '**/*.lua\n'
}
EOF

grep -c '^adapter_' adapters/lua.sh
```

You should see:

```
2
```

Checkpoint: `adapters/lua.sh` defines two of the four contract functions.

## Step 3: Write a runner that loads the adapter the way the harness does, then check detection. The harness sources the adapter file inside a subshell whose working directory is the workspace and calls one function, so a bug in your adapter can never leak state into the harness. Run detection twice: once against the Lua fixture, once against a repository with no rockspec. An adapter that claims a workspace it does not own is worse than one that claims nothing, because detection stops at the first adapter that returns success.

```sh
cat > run-adapter.sh <<'EOF'
#!/bin/sh
# run-adapter.sh ADAPTER WORKSPACE FUNC: source ADAPTER with the working
# directory at WORKSPACE and run one contract function, the way the harness
# does it.
set -eu
_adapter=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$2"
. "$_adapter"
"$3"
EOF

mkdir -p plain
(cd plain \
  && git init -q \
  && printf '# plain\n' > README.md \
  && git add -A \
  && git -c user.email=you@example.com -c user.name=you commit -q -m "plain")

if sh run-adapter.sh adapters/lua.sh fixture adapter_detect; then
  echo "fixture: lua"
else
  echo "fixture: not lua"
fi

if sh run-adapter.sh adapters/lua.sh plain adapter_detect; then
  echo "plain: lua"
else
  echo "plain: not lua"
fi

sh run-adapter.sh adapters/lua.sh fixture adapter_source_globs
```

You should see:

```
fixture: lua
plain: not lua
**/*.lua
```

Checkpoint: Detection claims the fixture and refuses the plain repository, and the source globs print one pattern.

## Step 4: Add `adapter_context_files`. These are the files the planning call reads for orientation rather than documentation: build metadata, the README, linter configuration, continuous integration workflows. End the function with `return 0`, because the last `[ -d ... ]` test fails whenever the directory is absent and that failure would otherwise become the function's exit status.

```sh
cat >> adapters/lua.sh <<'EOF'

adapter_context_files() {
  git ls-files -- '*.rockspec' 2>/dev/null
  for _f in Makefile README.md .luacheckrc; do
    [ -f "$_f" ] && printf '%s\n' "$_f"
  done
  for _d in .github/workflows docs/adr; do
    [ -d "$_d" ] && find "$_d" -type f | LC_ALL=C sort
  done
  return 0
}
EOF

sh run-adapter.sh adapters/lua.sh fixture adapter_context_files
```

You should see:

```
keys.rockspec
README.md
.luacheckrc
```

Checkpoint: Three context files print. The fixture has no Makefile and no workflow directory, and those absences produce no output and no error.

## Step 5: Add the fourth and largest function, `adapter_symbol_inventory`. It prints one JSON object per line, and every object carries the fields the citation contract needs: `name`, `kind`, `signature`, `path`, `line`, `visibility`, `doc_comment` and `strategy`. Lua has no symbol server to ask, so extraction is an awk pass over top-level declarations, exactly as the shell adapter does. The visibility convention here is Lua's own: a `local function` is internal, a plain `function` is public. Declarations indented inside a table or a closure are not top-level and stay out.

```sh
cat >> adapters/lua.sh <<'EOF'

# _lua_source_files: tracked .lua files, minus specs and tests.
_lua_source_files() {
  git ls-files -- '*.lua' 2>/dev/null \
    | grep -v -E '(^|/)(spec|tests?)/' \
    | LC_ALL=C sort -u
}

adapter_symbol_inventory() {
  _lua_source_files | while IFS= read -r _f; do
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
      /^[[:space:]]*--/ {
        d = $0
        sub(/^[[:space:]]*-+[[:space:]]?/, "", d)
        doc = doc (doc == "" ? "" : "\\n") jesc(d)
        next
      }
      /^(local[[:space:]]+)?function[[:space:]]+[A-Za-z_]/ {
        line = $0
        vis = (line ~ /^local/) ? "internal" : "public"
        sig = line
        sub(/^local[[:space:]]+/, "", sig)
        name = sig
        sub(/^function[[:space:]]+/, "", name)
        sub(/[[:space:]]*\(.*$/, "", name)
        sub(/^.*[.:]/, "", name)
        if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/) { doc = ""; next }
        emit(name, "function", sig, vis)
        next
      }
      /^[A-Z][A-Z0-9_]*[[:space:]]*=/ {
        name = $0
        sub(/[[:space:]]*=.*$/, "", name)
        sig = $0
        sub(/[[:space:]]*--.*$/, "", sig)
        emit(name, "constant", sig, "public")
        next
      }
      { doc = "" }
    ' "$_f"
  done
}
EOF

sh run-adapter.sh adapters/lua.sh fixture adapter_symbol_inventory \
  | jq -c '{name, kind, visibility, line}'
```

You should see:

```
{"name":"usage","kind":"function","visibility":"public","line":5}
{"name":"KEY_ROTATION_LIMIT","kind":"constant","visibility":"public","line":4}
{"name":"rotate_key","kind":"function","visibility":"public","line":7}
{"name":"check_id","kind":"function","visibility":"internal","line":13}
```

Checkpoint: All four contract functions exist, and the inventory emits four records: one from `bin/keytool.lua` and three from `src/keys.lua`. `test_rotate_key` from the spec file is absent, and `check_id` is marked internal. Each line is valid JSON, which is why `jq` can reshape it.

## Step 6: Pin that output with a golden file and compare. This is the check you will keep: it fails loudly the moment a regex change shifts a line number, drops a symbol, or mangles a signature. Compare a projection of the fields rather than whole records, so the assertion stays readable, then confirm separately that the doc comment above `rotate_key` reached the record.

```sh
cat > golden-inventory.json <<'EOF'
[
  {"name":"usage","kind":"function","visibility":"public","path":"bin/keytool.lua","line":5,"signature":"function usage()"},
  {"name":"KEY_ROTATION_LIMIT","kind":"constant","visibility":"public","path":"src/keys.lua","line":4,"signature":"KEY_ROTATION_LIMIT = 5"},
  {"name":"rotate_key","kind":"function","visibility":"public","path":"src/keys.lua","line":7,"signature":"function M.rotate_key(id)"},
  {"name":"check_id","kind":"function","visibility":"internal","path":"src/keys.lua","line":13,"signature":"function check_id(id)"}
]
EOF

sh run-adapter.sh adapters/lua.sh fixture adapter_symbol_inventory \
  | jq -sS 'map({name, kind, visibility, path, line, signature})' \
  > actual-inventory.json

if [ "$(jq -S . actual-inventory.json)" = "$(jq -S . golden-inventory.json)" ]; then
  echo "inventory matches the golden file"
else
  echo "inventory does not match the golden file"
  jq -S . actual-inventory.json
  exit 1
fi

sh run-adapter.sh adapters/lua.sh fixture adapter_symbol_inventory \
  | jq -sr '(map(select(.name == "rotate_key")) | .[0].doc_comment)'
```

You should see:

```
inventory matches the golden file
Rotate the signing key identified by id.
```

Checkpoint: The golden inventory comparison passes, and the comment line above `rotate_key` is carried on the record as its `doc_comment`. Every path in the golden file is workspace-relative, which is what lets the harness prefix it with the workspace path in a monorepo.

## Step 7: Run the second golden comparison, over the plan the harness derives from your inventory. Reference pages are not invented by the model: the harness groups your inventory records by module, one page per module, mirroring the source tree, and strips a leading `src/` so a module at the root takes the workspace directory name. The jq program below is the harness's own derivation, so the pages it prints are the pages a real `diataxis plan` would put in `plan.json`.

```sh
cat > golden-pages.json <<'EOF'
[
  {"slug":"reference/bin","mode":"reference","title":"bin reference","rationale":"derived mechanically from the symbol inventory","sources":["bin/keytool.lua"],"priority":2,"audience":"developer"},
  {"slug":"reference/fixture","mode":"reference","title":"fixture reference","rationale":"derived mechanically from the symbol inventory","sources":["src/keys.lua"],"priority":2,"audience":"developer"}
]
EOF

sh run-adapter.sh adapters/lua.sh fixture adapter_symbol_inventory \
  | jq -s --arg root fixture '
      def module_of($p):
        ($p | split("/")[0:-1] | join("/")) as $d
        | ($d | sub("^src/?"; "")) as $m
        | if $m == "" or $m == "." then $root else $m end;
      group_by(module_of(.path))
      | map({
          slug: ("reference/" + module_of(.[0].path)),
          mode: "reference",
          title: (module_of(.[0].path) + " reference"),
          rationale: "derived mechanically from the symbol inventory",
          sources: ([.[].path] | unique),
          priority: 2,
          audience: "developer"
        })
      | sort_by(.slug)' \
  > actual-pages.json

if [ "$(jq -S . actual-pages.json)" = "$(jq -S . golden-pages.json)" ]; then
  echo "derived reference pages match the golden plan"
else
  echo "derived reference pages do not match the golden plan"
  jq -S . actual-pages.json
  exit 1
fi
```

You should see:

```
derived reference pages match the golden plan
```

Checkpoint: Both golden comparisons pass. Your adapter is finished: it detects its workspaces, declares its source globs, offers context files, and produces an inventory that drives two reference pages named `reference/bin` and `reference/fixture`.

## Step 8: Install the adapter into a claude-diataxis checkout and register it with detection. Replace `CHECKOUT` with the path to your checkout; this step acts on your checkout rather than on the tutorial directory, so run each line yourself. The adapter goes in `lib/adapters/` under the name detection uses, the fixture becomes `tests/fixtures/lua/repo` with its git directory removed (the test helper's `make_repo` copies the fixture and initialises a fresh repository), and `lua` joins the detection order before `shell`, because the shell adapter deliberately sits last and claims any workspace no other adapter recognises.

```text
cp adapters/lua.sh CHECKOUT/lib/adapters/lua.sh

mkdir -p CHECKOUT/tests/fixtures/lua/repo CHECKOUT/tests/fixtures/lua/responses
cp -R fixture/. CHECKOUT/tests/fixtures/lua/repo/
rm -rf CHECKOUT/tests/fixtures/lua/repo/.git
cp golden-pages.json CHECKOUT/tests/fixtures/lua/golden-plan.json

In CHECKOUT/bin/diataxis, inside detect_adapter, change the loop to:

  for _a in rust go python typescript lua shell; do

In CHECKOUT/tests/fixtures.bats, add two tests next to the existing ones:

  @test "lua: init detects the adapter" { detects_adapter lua proj-lua lua; }
  @test "lua: plan matches the golden plan" { plan_matches_golden lua proj-lua; }

Then run:

  bats CHECKOUT/tests/fixtures.bats
```

Checkpoint: The detection test passes on its own. The plan test also needs `tests/fixtures/lua/responses/plan.json`, a recorded model response for the stub, and the fixture directory name `proj-lua` has to match the root module name in `golden-plan.json`, so change `reference/fixture` to `reference/proj-lua` in that file.

## Next steps

- [explanation/language-adapter-architecture](../explanation/language-adapter-architecture.md)
- [reference/lib/adapters](../reference/lib/adapters.md)
- [how-to/run-the-harness-test-suite](../how-to/run-the-harness-test-suite.md)
- [how-to/configure-a-multi-language-monorepo](../how-to/configure-a-multi-language-monorepo.md)

