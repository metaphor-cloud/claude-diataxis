# shellcheck shell=sh
# preamble.sh: runtime helpers, environment and auth checks.
# Sourced by bin/diataxis before anything else. POSIX sh, Bash 3.2 compatible.

# --- exit codes ---------------------------------------------------------------
# Documented in README.md. 14, 15 and 16 are additions beyond the spec's list,
# chosen so every doctor check has a distinct code.
EX_OK=0
EX_GENERIC=1
EX_CONFIG=2
EX_CLAUDE_MISSING=10
EX_CLAUDE_OLD=11
EX_UNAUTH=12
EX_JQ_MISSING=13
EX_GIT_MISSING=14
EX_UNWRITABLE=15
EX_NOT_BARE_CAPABLE=16
EX_BUDGET=20
EX_MODEL_UNAVAILABLE=21
EX_AUDIT_FAILED=30
EX_STALE=31
EX_VERIFY_FAILED=32
export EX_OK EX_GENERIC EX_CONFIG EX_CLAUDE_MISSING EX_CLAUDE_OLD EX_UNAUTH \
  EX_JQ_MISSING EX_GIT_MISSING EX_UNWRITABLE EX_NOT_BARE_CAPABLE EX_BUDGET \
  EX_MODEL_UNAVAILABLE EX_AUDIT_FAILED EX_STALE EX_VERIFY_FAILED

DIATAXIS_MIN_CLAUDE_VERSION="2.1.205"
DIATAXIS_MIN_JQ_VERSION="1.6"

# --- output helpers -----------------------------------------------------------

setup_colors() {
  C_RED='' C_GRN='' C_YLW='' C_OFF=''
  if [ "${DIATAXIS_NO_COLOR:-0}" -eq 0 ] && [ -z "${NO_COLOR:-}" ] && [ -t 2 ]; then
    C_RED="$(printf '\033[31m')"
    C_GRN="$(printf '\033[32m')"
    C_YLW="$(printf '\033[33m')"
    C_OFF="$(printf '\033[0m')"
  fi
}

log() { printf '%s\n' "$*" >&2; }

warn() { printf '%swarning:%s %s\n' "${C_YLW:-}" "${C_OFF:-}" "$*" >&2; }

verbose() {
  if [ "${DIATAXIS_VERBOSE:-0}" -eq 1 ]; then
    printf '%s\n' "$*" >&2
  fi
}

die() {
  _code=$1
  shift
  printf '%serror:%s %s\n' "${C_RED:-}" "${C_OFF:-}" "$*" >&2
  exit "$_code"
}

# --- small utilities ----------------------------------------------------------

# version_ge A B: exit 0 when dot-separated version A >= B.
version_ge() {
  awk -v v1="$1" -v v2="$2" 'BEGIN {
    n1 = split(v1, a, ".")
    n2 = split(v2, b, ".")
    n = (n1 > n2) ? n1 : n2
    for (i = 1; i <= n; i++) {
      x = a[i] + 0
      y = b[i] + 0
      if (x > y) exit 0
      if (x < y) exit 1
    }
    exit 0
  }'
}

# sha256_stream: hash stdin, print the bare hex digest.
# Handles the BSD (shasum) vs GNU (sha256sum) split once.
sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

sha256_file() { sha256_stream <"$1"; }

# b64_decode: decode base64 from stdin. BSD base64 historically only takes -D;
# GNU and current macOS take -d. Probe once.
b64_decode() {
  if [ -z "${DIATAXIS_B64_FLAG:-}" ]; then
    if printf 'b2s=' | base64 -d >/dev/null 2>&1; then
      DIATAXIS_B64_FLAG='-d'
    else
      DIATAXIS_B64_FLAG='-D'
    fi
    export DIATAXIS_B64_FLAG
  fi
  base64 "$DIATAXIS_B64_FLAG"
}

sha256_string() { printf '%s' "$1" | sha256_stream; }

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# render_template FILE: substitute ${NAME} occurrences from the environment.
# envsubst-style, ${VAR} form only, single pass (values are not re-expanded).
render_template() {
  awk '{
    out = ""
    rest = $0
    while (match(rest, /\$\{[A-Za-z_][A-Za-z0-9_]*\}/)) {
      name = substr(rest, RSTART + 2, RLENGTH - 3)
      out = out substr(rest, 1, RSTART - 1) ENVIRON[name]
      rest = substr(rest, RSTART + RLENGTH)
    }
    print out rest
  }' "$1"
}

# awk_float_lt A B: exit 0 when A < B (floating point).
awk_float_lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 < b + 0) }'; }

# awk_float_sub A B: print A - B.
awk_float_sub() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.4f", a - b }'; }

# awk_float_add A B: print A + B.
awk_float_add() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.4f", a + b }'; }

# --- doctor checks ------------------------------------------------------------
# Each check dies with its distinct exit code and a remediation line on failure.
# When DIATAXIS_DOCTOR_PRINT=1 each success is also reported.

doctor_ok() {
  if [ "${DIATAXIS_DOCTOR_PRINT:-0}" -eq 1 ]; then
    printf '%s  ok%s  %s\n' "${C_GRN:-}" "${C_OFF:-}" "$*" >&2
  fi
}

doctor_fail() {
  _code=$1
  shift
  printf '%sfail%s  %s\n' "${C_RED:-}" "${C_OFF:-}" "$*" >&2
  exit "$_code"
}

check_claude_on_path() {
  if ! command -v claude >/dev/null 2>&1; then
    doctor_fail "$EX_CLAUDE_MISSING" \
      "claude not found on PATH. Install with: npm i -g @anthropic-ai/claude-code"
  fi
  doctor_ok "claude on PATH ($(command -v claude))"
}

check_claude_version() {
  DIATAXIS_CLAUDE_VERSION=$(claude --version </dev/null 2>/dev/null | awk '{print $1; exit}')
  if [ -z "$DIATAXIS_CLAUDE_VERSION" ]; then
    doctor_fail "$EX_CLAUDE_OLD" \
      "could not parse 'claude --version' output. Reinstall with: npm i -g @anthropic-ai/claude-code"
  fi
  if ! version_ge "$DIATAXIS_CLAUDE_VERSION" "$DIATAXIS_MIN_CLAUDE_VERSION"; then
    doctor_fail "$EX_CLAUDE_OLD" \
      "claude $DIATAXIS_CLAUDE_VERSION is older than $DIATAXIS_MIN_CLAUDE_VERSION. --json-schema validation and /model as argument landed there; older versions silently ignore an invalid schema. Update with: claude update"
  fi
  doctor_ok "claude version $DIATAXIS_CLAUDE_VERSION (minimum $DIATAXIS_MIN_CLAUDE_VERSION)"
  export DIATAXIS_CLAUDE_VERSION
}

check_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    doctor_fail "$EX_JQ_MISSING" \
      "jq not found on PATH. Install jq 1.6 or newer (brew install jq / apt-get install jq)"
  fi
  _jqv=$(jq --version 2>/dev/null | sed 's/^jq-//; s/[^0-9.].*$//')
  if [ -z "$_jqv" ] || ! version_ge "$_jqv" "$DIATAXIS_MIN_JQ_VERSION"; then
    doctor_fail "$EX_JQ_MISSING" \
      "jq ${_jqv:-unknown} is older than $DIATAXIS_MIN_JQ_VERSION. Install jq 1.6 or newer"
  fi
  doctor_ok "jq $_jqv (minimum $DIATAXIS_MIN_JQ_VERSION)"
}

check_git() {
  if ! command -v git >/dev/null 2>&1; then
    doctor_fail "$EX_GIT_MISSING" "git not found on PATH. Install git"
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    doctor_fail "$EX_GIT_MISSING" \
      "not inside a git work tree. Run diataxis from within the repository to document"
  fi
  DIATAXIS_WORKSPACE=$(git rev-parse --show-toplevel)
  export DIATAXIS_WORKSPACE
  doctor_ok "git work tree at $DIATAXIS_WORKSPACE"
}

# claude_auth_status_supported: exit 0 when the installed CLI has `auth status`.
claude_auth_status_supported() {
  claude auth --help </dev/null 2>/dev/null | grep -q '^  status'
}

check_auth() {
  DIATAXIS_AUTH_METHOD=''
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    DIATAXIS_AUTH_METHOD="oauth_token_env"
  elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    DIATAXIS_AUTH_METHOD="api_key_env"
  elif claude_auth_status_supported; then
    _auth_json=$(claude auth status --json </dev/null 2>/dev/null) || _auth_json=''
    if [ -n "$_auth_json" ] && printf '%s' "$_auth_json" | jq -e . >/dev/null 2>&1; then
      DIATAXIS_AUTH_METHOD=$(printf '%s' "$_auth_json" | jq -r '.method // "subscription"')
    fi
    if [ -z "$DIATAXIS_AUTH_METHOD" ]; then
      # `claude auth status` exists but reported unauthenticated (or emitted
      # something unparseable). Do not probe: probing spends money and cannot
      # succeed if the CLI itself says we are logged out.
      doctor_fail "$EX_UNAUTH" "Claude CLI is not authenticated. Run: claude auth login
For CI, generate a long-lived token with: claude setup-token
then export CLAUDE_CODE_OAUTH_TOKEN, or export ANTHROPIC_API_KEY."
    fi
  else
    # Older CLI without `auth status`. Probe once, cheaply.
    if claude -p 'reply with the single word ok' --model claude-haiku-4-5 \
        --max-turns 1 --strict-mcp-config --output-format json \
        </dev/null 2>/dev/null \
        | jq -e '.result | length > 0' >/dev/null 2>&1; then
      DIATAXIS_AUTH_METHOD="probe_ok"
    else
      doctor_fail "$EX_UNAUTH" "Claude CLI is not authenticated. Run: claude auth login
For CI, generate a long-lived token with: claude setup-token
then export CLAUDE_CODE_OAUTH_TOKEN, or export ANTHROPIC_API_KEY."
    fi
  fi
  export DIATAXIS_AUTH_METHOD
  doctor_ok "authenticated (method: $DIATAXIS_AUTH_METHOD)"
}

check_writable() {
  _docs_dir=${1:-docs}
  for _d in "$DIATAXIS_WORKSPACE/$_docs_dir" "$DIATAXIS_WORKSPACE/.diataxis"; do
    if [ -d "$_d" ]; then
      if [ ! -w "$_d" ]; then
        doctor_fail "$EX_UNWRITABLE" "$_d exists but is not writable"
      fi
    else
      if [ ! -w "$DIATAXIS_WORKSPACE" ]; then
        doctor_fail "$EX_UNWRITABLE" \
          "$DIATAXIS_WORKSPACE is not writable, cannot create $_d"
      fi
    fi
  done
  doctor_ok "writable: $_docs_dir/ and .diataxis/"
}

# resolve_bare: decide whether --bare is passed to claude, from the auth
# method and the config `bare` key ("auto" | true | false).
#
# --bare skips hooks, plugins, CLAUDE.md and auto memory, which is what makes
# runs reproducible. It also skips OAuth and keychain reads, so it only works
# when credentials come from the environment (ANTHROPIC_API_KEY,
# CLAUDE_CODE_OAUTH_TOKEN) or an apiKeyHelper supplied via --settings.
resolve_bare() {
  _cfg_bare=${1:-auto}
  _settings_file=${2:-}
  DIATAXIS_BARE_CAPABLE=0
  case "$DIATAXIS_AUTH_METHOD" in
    api_key_env|oauth_token_env) DIATAXIS_BARE_CAPABLE=1 ;;
    *)
      if [ -n "$_settings_file" ]; then
        # A settings file may carry an apiKeyHelper; trust the operator.
        DIATAXIS_BARE_CAPABLE=1
      fi
      ;;
  esac
  case "$_cfg_bare" in
    false)
      DIATAXIS_USE_BARE=0
      ;;
    true)
      if [ "$DIATAXIS_BARE_CAPABLE" -eq 1 ]; then
        DIATAXIS_USE_BARE=1
      else
        die "$EX_NOT_BARE_CAPABLE" \
          "config sets \"bare\": true but auth method '$DIATAXIS_AUTH_METHOD' cannot work in bare mode. Export ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN, or supply an apiKeyHelper via settings_file"
      fi
      ;;
    *)
      DIATAXIS_USE_BARE=$DIATAXIS_BARE_CAPABLE
      if [ "$DIATAXIS_BARE_CAPABLE" -eq 0 ]; then
        warn "auth method '$DIATAXIS_AUTH_METHOD' is not bare-capable; running without --bare. Local CLAUDE.md, hooks and plugins will be in context, so output may not match CI"
      fi
      ;;
  esac
  export DIATAXIS_BARE_CAPABLE DIATAXIS_USE_BARE
}

require_bare_capable() {
  if [ "${DIATAXIS_BARE_CAPABLE:-0}" -ne 1 ]; then
    die "$EX_NOT_BARE_CAPABLE" \
      "diataxis check requires bare-capable auth so CI runs are reproducible. Export ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN (claude setup-token), or supply an apiKeyHelper via settings_file"
  fi
}

# probe_models: live-probe each configured model once. Costs money, so it only
# runs from `diataxis doctor` when DIATAXIS_LIVE=1.
probe_models() {
  _models=$1 # newline-separated unique model ids
  # shellcheck disable=SC2086 # word splitting over the model list is intended
  for _m in $_models; do
    verbose "probing model $_m"
    set -- -p 'reply with the single word ok' --model "$_m" --max-turns 1 \
      --strict-mcp-config --output-format json
    if [ "${DIATAXIS_USE_BARE:-0}" -eq 1 ]; then
      set -- --bare "$@"
    fi
    if ! claude "$@" </dev/null 2>/dev/null \
        | jq -e '.result | length > 0' >/dev/null 2>&1; then
      doctor_fail "$EX_MODEL_UNAVAILABLE" \
        "model '$_m' is not available or not permitted for this account. Adjust the models block in diataxis.config.json"
    fi
    doctor_ok "model $_m permitted"
  done
}

# preamble_run: the fast check sequence that runs inside every subcommand.
preamble_run() {
  check_claude_on_path
  check_claude_version
  check_jq
  check_git
  check_auth
}
