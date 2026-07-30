# shellcheck shell=sh
# render.sh: render structured generation output to Markdown with YAML
# frontmatter. Prose is generated, layout is not: these templates are the
# layout. Output is plain Markdown consumable by MkDocs, Docusaurus, mdBook
# and Hugo.

# render_frontmatter SLUG MODE TITLE VERIFIED
# VERIFIED is "true", "false", or "" (omitted for non-tutorial modes).
render_frontmatter() {
  printf -- '---\n'
  printf 'title: "%s"\n' "$(printf '%s' "$3" | sed 's/"/\\"/g')"
  printf 'slug: %s\n' "$1"
  printf 'mode: %s\n' "$2"
  printf 'generated_by: diataxis\n'
  printf 'generated_at: %s\n' "$(iso_now)"
  if [ -n "${4:-}" ]; then
    printf 'verified: %s\n' "$4"
  fi
  printf 'frozen: false\n'
  printf -- '---\n\n'
}

# Each renderer reads the structured JSON on stdin and writes the Markdown
# body (no frontmatter) on stdout.

render_reference_body() {
  jq -r '
    def cite: "`\(.path)`" + (if .line_range then " (lines \(.line_range))" else "" end);
    "# \(.title)\n\n\(.summary)\n",
    (.symbols[] |
      "## `\(.name)`\n" +
      "\n*\(.kind)*" +
      (if .stability and .stability != "stable" then ", *\(.stability)*" else "" end) +
      (if .since then ", since \(.since)" else "" end) + "\n" +
      "\n```\n\(.signature)\n```\n" +
      "\n\(.description)\n" +
      (if (.parameters // []) | length > 0 then
        "\n| Parameter | Type | Description |\n| --- | --- | --- |\n" +
        ([.parameters[] |
          "| `\(.name)`\(if .optional then " (optional)" else "" end) | `\(.type)` | \(.description) |"
         ] | join("\n")) + "\n"
      else "" end) +
      (if .returns then "\nReturns: \(.returns)\n" else "" end) +
      (if (.raises // []) | length > 0 then
        "\nRaises:\n" + ([.raises[] | "- \(.)"] | join("\n")) + "\n"
      else "" end) +
      (if (.citations // []) | length > 0 then
        "\nSource: " + ([.citations[] | cite] | join(", ")) + "\n"
      else "" end)
    )'
}

# Related links are rendered relative to the page location under docs/.
render_related_jq() {
  cat <<'EOF'
def uplevels($slug): ($slug | split("/") | length - 1) as $n
  | if $n <= 0 then "" else ([range(0; $n) | "../"] | join("")) end;
def rel_link($from; $to): uplevels($from) + $to + ".md";
EOF
}

render_howto_body() {
  jq -r --arg slug "$1" "$(render_related_jq)"'
    "# \(.title)\n\n\(.goal)\n",
    (if (.assumes // []) | length > 0 then
      "## Before you start\n\n" + ([.assumes[] | "- \(.)"] | join("\n")) + "\n"
    else "" end),
    "## Steps\n",
    (.steps | to_entries[] |
      "\(.key + 1). \(.value.instruction)\n" +
      (if .value.code then
        "\n   ```\(.value.language // "")\n" +
        (.value.code | split("\n") | map("   " + .) | join("\n")) +
        "\n   ```\n"
      else "" end) +
      (if .value.expected_result then "\n   Expected result: \(.value.expected_result)\n" else "" end)
    ),
    "## Verify it worked\n\n\(.verification)\n",
    (if (.related // []) | length > 0 then
      "## Related\n\n" +
      ([.related[] | "- [\(.slug)](\(rel_link($slug; .slug)))"] | join("\n")) + "\n"
    else "" end)'
}

render_tutorial_body() {
  jq -r --arg slug "$1" "$(render_related_jq)"'
    "# \(.title)\n\nIn this tutorial you will build: \(.outcome)\n\nTime: about \(.time_estimate_minutes) minutes.\n",
    (if (.prerequisites // []) | length > 0 then
      "## What you need\n\n" + ([.prerequisites[] | "- \(.)"] | join("\n")) + "\n"
    else "" end),
    (.steps | to_entries[] |
      "## Step \(.key + 1): \(.value.instruction)\n" +
      (if .value.code then
        "\n```\(.value.language // "")\n\(.value.code)\n```\n"
      else "" end) +
      (if .value.expected_output then
        "\nYou should see:\n\n```\n\(.value.expected_output)\n```\n"
      else "" end) +
      (if .value.checkpoint then "\nCheckpoint: \(.value.checkpoint)\n" else "" end)
    ),
    (if (.next_steps // []) | length > 0 then
      "## Next steps\n\n" +
      ([.next_steps[] | "- [\(.slug)](\(rel_link($slug; .slug)))"] | join("\n")) + "\n"
    else "" end)'
}

render_explanation_body() {
  jq -r --arg slug "$1" "$(render_related_jq)"'
    "# \(.title)\n\n\(.thesis)\n",
    (.sections[] | "## \(.heading)\n\n\(.body)\n"),
    (if (.tradeoffs // []) | length > 0 then
      "## Tradeoffs\n\n| Decision | Chose | Rejected | Because |\n| --- | --- | --- | --- |\n" +
      ([.tradeoffs[] | "| \(.decision) | \(.chose) | \(.rejected) | \(.because) |"] | join("\n")) + "\n"
    else "" end),
    (if (.open_questions // []) | length > 0 then
      "## Open questions\n\n" + ([.open_questions[] | "- \(.)"] | join("\n")) + "\n"
    else "" end),
    (if (.related // []) | length > 0 then
      "## Related\n\n" +
      ([.related[] | "- [\(.slug)](\(rel_link($slug; .slug)))"] | join("\n")) + "\n"
    else "" end)'
}

# render_page MODE SLUG TITLE VERIFIED < structured.json > page.md
render_page() {
  _mode=$1
  _slug=$2
  _title=$3
  _verified=${4:-}
  render_frontmatter "$_slug" "$_mode" "$_title" "$_verified"
  case "$_mode" in
    reference) render_reference_body ;;
    howto) render_howto_body "$_slug" ;;
    tutorial) render_tutorial_body "$_slug" ;;
    explanation) render_explanation_body "$_slug" ;;
    *) die "$EX_GENERIC" "no renderer for mode $_mode" ;;
  esac
}

# render_audit_findings < findings.json: human-readable finding lines.
render_audit_findings() {
  jq -r '.findings[]? |
    "\(.severity)\t\(.path)\t\(.rule)\t\(.excerpt // "" | gsub("\n"; " ") | .[0:80])\t\(.suggestion // "" | gsub("\n"; " "))"' \
  | awk -F '\t' '{
      printf "%-7s %s  [%s]\n", $1":", $2, $3
      if ($4 != "") printf "        excerpt: %s\n", $4
      if ($5 != "") printf "        suggestion: %s\n", $5
    }'
}
