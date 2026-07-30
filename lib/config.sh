# shellcheck shell=sh
# config.sh: load diataxis.config.json, validate against schemas/config.json,
# merge defaults, expose accessors. jq is the only parser.

# config_default_json: the full default config. Kept in sync with
# share/diataxis.config.example.json.
config_default_json() {
  cat <<'EOF'
{
  "version": 1,
  "docs_dir": "docs",
  "workspaces": [{"path": ".", "adapter": "auto", "name": null}],
  "include": ["src/**"],
  "exclude": ["**/testdata/**", "**/*_test.go", "**/node_modules/**"],
  "bare": "auto",
  "settings_file": null,
  "models": {
    "plan":           {"model": "claude-opus-5",   "effort": "high"},
    "tutorial":       {"model": "claude-opus-5",   "effort": "high"},
    "explanation":    {"model": "claude-opus-5",   "effort": "high"},
    "howto":          {"model": "claude-sonnet-5", "effort": "medium"},
    "reference":      {"model": "claude-sonnet-5", "effort": "medium"},
    "reference_bulk": {"model": "claude-haiku-4-5"},
    "audit":          {"model": "claude-sonnet-5", "effort": "medium"},
    "fallback":       "claude-sonnet-5"
  },
  "budget_usd": 50.0,
  "verify": {
    "mode": "sandbox",
    "required": true,
    "max_repairs": 2,
    "executable_languages": ["bash", "sh", "console"]
  },
  "audit": {"fail_on": ["error"], "model_audit_in_check": false},
  "voice": {"style_guide": "google", "person": "second", "extra_instructions_file": null}
}
EOF
}

# config_validate_jq: a JSON Schema validator for the subset used by
# schemas/config.json (type, enum, required, properties, additionalProperties,
# items). Emits one line per violation as "<json pointer>: <message>".
config_validate_jq() {
  cat <<'EOF'
def resolve($s):
  if ($s | type) == "object" and ($s | has("$ref"))
  then $schema.definitions[$s["$ref"] | ltrimstr("#/definitions/")]
  else $s
  end;

def type_matches($want):
  . as $v
  | ($v | type) as $t
  | if $want == "integer" then ($t == "number" and ($v == ($v | floor)))
    else $t == $want
    end;

def errs($sin; $p):
  resolve($sin) as $s
  | if $s == null then []
    else
      (if ($s | has("type")) then
        ($s.type | if type == "array" then . else [.] end) as $types
        | . as $v
        | if any($types[]; . as $w | $v | type_matches($w)) then []
          else ["\($p): expected \($types | join(" or ")), got \($v | type)"]
          end
      else [] end) as $terr
      | if ($terr | length) > 0 then $terr
        else
          (if ($s | has("enum")) then
            (. as $v
             | if ($s.enum | index($v)) != null then []
               else ["\($p): value \($v | tojson) is not one of \($s.enum | tojson)"]
               end)
          else [] end)
          + (if type == "object" and ($s | has("required"))
             then (. as $o
                   | [$s.required[] as $r
                      | select(($o | has($r)) | not)
                      | "\($p)/\($r): required key missing"])
             else [] end)
          + (if type == "object" and ($s | has("properties"))
             then ([to_entries[]
                    | . as $e
                    | if ($s.properties | has($e.key))
                      then ($e.value | errs($s.properties[$e.key]; "\($p)/\($e.key)"))
                      elif ($s.additionalProperties == false)
                      then ["\($p)/\($e.key): unexpected key"]
                      else []
                      end] | add // [])
             else [] end)
          + (if type == "array" and ($s | has("items"))
             then ([range(0; length) as $i | (.[$i] | errs($s.items; "\($p)/\($i)"))] | add // [])
             else [] end)
        end
    end;

errs($schema; "") | .[]
EOF
}

# config_find_path: resolve the config file path. --config wins, then the
# workspace root. Prints nothing when no config exists.
config_find_path() {
  if [ -n "${DIATAXIS_CONFIG:-}" ]; then
    printf '%s\n' "$DIATAXIS_CONFIG"
    return 0
  fi
  if [ -f "$DIATAXIS_WORKSPACE/diataxis.config.json" ]; then
    printf '%s\n' "$DIATAXIS_WORKSPACE/diataxis.config.json"
  fi
}

# config_load [allow_missing]: populate DIATAXIS_CONFIG_JSON (defaults merged)
# and derived globals. Dies EX_CONFIG on invalid config. With allow_missing=1
# a missing file just yields the defaults.
config_load() {
  _allow_missing=${1:-0}
  _path=$(config_find_path)
  _user_json='{}'
  if [ -n "$_path" ]; then
    if [ ! -f "$_path" ]; then
      die "$EX_CONFIG" "config file not found: $_path"
    fi
    if ! _user_json=$(jq -c . "$_path" 2>&1); then
      die "$EX_CONFIG" "config is not valid JSON: $_path: $_user_json"
    fi
    _schema_file="$DIATAXIS_ROOT/schemas/config.json"
    _violations=$(printf '%s' "$_user_json" \
      | jq -r --argjson schema "$(jq -c . "$_schema_file")" "$(config_validate_jq)")
    if [ -n "$_violations" ]; then
      printf '%s\n' "$_violations" >&2
      die "$EX_CONFIG" "config invalid: $_path (first violation: $(printf '%s\n' "$_violations" | head -1))"
    fi
  else
    if [ "$_allow_missing" -ne 1 ]; then
      die "$EX_CONFIG" "no diataxis.config.json found in $DIATAXIS_WORKSPACE. Run: diataxis init"
    fi
  fi
  # Deep-merge user config over the defaults. jq's * merges objects
  # recursively; arrays and scalars from the user config replace defaults.
  DIATAXIS_CONFIG_JSON=$(config_default_json | jq -c --argjson user "$_user_json" '. * $user')
  export DIATAXIS_CONFIG_JSON
  DIATAXIS_CONFIG_PATH=$_path
  export DIATAXIS_CONFIG_PATH

  DIATAXIS_DOCS_DIR=$(cfg -r '.docs_dir')
  export DIATAXIS_DOCS_DIR

  # Cached so per-path glob matching does not spawn jq every time.
  DIATAXIS_INCLUDE_GLOBS=$(cfg -r '.include[]')
  DIATAXIS_EXCLUDE_GLOBS=$(cfg -r '.exclude[]')
  export DIATAXIS_INCLUDE_GLOBS DIATAXIS_EXCLUDE_GLOBS

  # The --budget-usd flag overrides the config value.
  if [ -z "${DIATAXIS_BUDGET_USD:-}" ]; then
    DIATAXIS_BUDGET_USD=$(cfg -r '.budget_usd')
  fi
  export DIATAXIS_BUDGET_USD
}

# cfg [-r] FILTER: query the merged config.
cfg() {
  if [ "$1" = "-r" ]; then
    printf '%s' "$DIATAXIS_CONFIG_JSON" | jq -r "$2"
  else
    printf '%s' "$DIATAXIS_CONFIG_JSON" | jq -c "$1"
  fi
}

# cfg_model MODE / cfg_effort MODE: model routing lookups.
cfg_model() {
  cfg -r ".models[\"$1\"].model // empty"
}

cfg_effort() {
  cfg -r ".models[\"$1\"].effort // empty"
}

cfg_settings_file() {
  cfg -r '.settings_file // empty'
}

# cfg_all_models: unique model ids configured, one per line.
cfg_all_models() {
  cfg -r '.models | to_entries[] | if (.value | type) == "object" then .value.model else .value end' \
    | sort -u
}

# config_style_instructions: the voice conventions injected into every system
# prompt, derived from voice.style_guide.
config_style_instructions() {
  _guide=$(cfg -r '.voice.style_guide // "google"')
  _person=$(cfg -r '.voice.person // "second"')
  cat <<EOF

## Voice and style

Follow the $_guide developer documentation style guide conventions:
- Sentence case for all headings.
- Write in the $_person person, present tense, active voice.
- Never use the words "simply", "just", "easy", or "obviously".
- Spell out every acronym at first use.
EOF
  _extra=$(cfg -r '.voice.extra_instructions_file // empty')
  if [ -n "$_extra" ] && [ -f "$DIATAXIS_WORKSPACE/$_extra" ]; then
    printf '\n'
    cat "$DIATAXIS_WORKSPACE/$_extra"
  fi
}
