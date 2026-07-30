---
title: "Generate your first documentation set"
slug: tutorials/generate-your-first-documentation-set
mode: tutorial
generated_by: diataxis
generated_at: 2026-07-29T21:12:52Z
verified: true
frozen: false
---

# Generate your first documentation set

In this tutorial you will build: a small Python repository with the diataxis harness vendored into it, a starter config, a reviewed .diataxis/plan.json, a docs/ tree of generated tutorial, how-to, reference and explanation pages, and a passing `diataxis check`

Time: about 30 minutes.

## What you need

- macOS or Linux with a POSIX shell.
- The Claude command-line interface (CLI) version 2.1.205 or newer on your PATH, already signed in. Check with `claude --version`.
- jq 1.6 or newer and git on your PATH. Check with `jq --version` and `git --version`.
- A local clone of the claude-diataxis repository. You vendor the harness out of that clone.
- An Anthropic account that can spend a few dollars. This run costs roughly one to three dollars of model usage.

## Step 1: Confirm that the three runtime dependencies are present and new enough, because the harness refuses to run without them.

```bash
git --version
jq --version
claude --version
```

You should see:

```
git version 2.39.5 (Apple Git-154)
jq-1.7.1
2.1.220 (Claude Code)
```

Checkpoint: Your versions differ, and that is fine, as long as jq is 1.6 or newer and the Claude CLI is 2.1.205 or newer. If a command prints "command not found", install that tool before you continue.

## Step 2: Create the small Python repository that you document in this tutorial, and commit it, because the harness reads tracked files through `git ls-files`.

```bash
mkdir -p greeter/src/greeter
cd greeter

cat > pyproject.toml <<'EOF'
[project]
name = "greeter"
version = "0.1.0"
description = "Greets people in a handful of languages."
EOF

cat > README.md <<'EOF'
# greeter

A tiny library that returns a greeting for a name in a chosen language.
EOF

cat > src/greeter/__init__.py <<'EOF'
from greeter.greet import GREETINGS, greet, greeting_for
EOF

cat > src/greeter/greet.py <<'EOF'
"""Greetings in a handful of languages."""

GREETINGS = {"en": "Hello", "fr": "Bonjour", "de": "Guten Tag"}


def greeting_for(language):
    """Return the greeting word for a language code."""
    if language not in GREETINGS:
        raise ValueError(f"unknown language: {language}")
    return GREETINGS[language]


def greet(name, language="en"):
    """Return a full greeting for name in language."""
    return f"{greeting_for(language)}, {name}!"
EOF

git init -q
git config user.email you@example.com
git config user.name "You"
git add .
git commit -q -m "Initial commit"
git log --oneline
```

You should see:

```
9f1c2ab Initial commit
```

Checkpoint: You have a git repository named greeter with one commit holding four files. Your commit hash differs from the one above, and git may also print a hint about the default branch name, which changes nothing here. You never run this Python code, so you do not need Python installed.

## Step 3: Vendor the harness into the repository by running `install.sh` from your clone, replacing `../claude-diataxis` with the path to that clone, then commit what it copied.

```text
../claude-diataxis/install.sh .
git add diataxis diataxis.config.json
git commit -q -m "Vendor the diataxis documentation harness"
```

You should see:

```
wrote ./diataxis.config.json (starter config)
vendored diataxis into ./diataxis
next steps:
  1. commit the diataxis/ directory
  2. run: ./diataxis/bin/diataxis doctor
  3. run: ./diataxis/bin/diataxis init && ./diataxis/bin/diataxis plan
```

Checkpoint: The repository now contains an executable `diataxis/bin/diataxis` and a starter `diataxis.config.json` at its root, both committed. The install script copied the bin, lib, prompts, schemas and share directories, so the harness travels with your repository.

## Step 4: Create a long-lived token and export it, so that every call runs in bare mode and produces the same output on your machine as in continuous integration (CI).

```text
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-REPLACE-WITH-YOUR-TOKEN
printenv CLAUDE_CODE_OAUTH_TOKEN | cut -c1-12
```

You should see:

```
sk-ant-oat01
```

Checkpoint: `claude setup-token` opens a browser to authorize the token and then prints it, starting with `sk-ant-oat01-`. Paste that value into the export command. Treat the token as a password and keep it out of commits. The harness only passes `--bare` when credentials come from the environment, and `diataxis check` in step 13 requires that.

## Step 5: Run the environment and authentication checks.

```text
./diataxis/bin/diataxis doctor
```

You should see:

```
  ok  claude on PATH (/opt/homebrew/bin/claude)
  ok  claude version 2.1.220 (minimum 2.1.205)
  ok  jq 1.7.1 (minimum 1.6)
  ok  git work tree at /Users/you/greeter
  ok  authenticated (method: oauth_token_env)
  ok  writable: docs/ and .diataxis/
  ok  model probe skipped (set DIATAXIS_LIVE=1 to live-probe configured models)
doctor: all checks passed
```

Checkpoint: Every line starts with `ok` and the last line reads "doctor: all checks passed". The authentication method reads `oauth_token_env`, which confirms that step 4 worked. Any failing check exits with its own code, such as 12 for unauthenticated or 13 for a missing jq.

## Step 6: Scaffold the documentation directories and the harness state directory.

```text
./diataxis/bin/diataxis init
find docs -type d | sort
```

You should see:

```
warning: diataxis.config.json already exists, leaving it untouched
scaffolded docs/{tutorials,how-to,reference,explanation}/ and .diataxis/
docs
docs/explanation
docs/how-to
docs/reference
docs/tutorials
```

Checkpoint: The four Diataxis directories exist under docs/, and `.diataxis/` exists alongside them. The warning is expected: `install.sh` already wrote the config in step 3, and `init` never overwrites a config that is already there.

## Step 7: Add the vendored harness to the exclude list, because the harness ships a Python file of its own that the plan would otherwise document instead of your code.

```text
jq '.exclude += ["diataxis/**"]' diataxis.config.json > config.tmp
mv config.tmp diataxis.config.json
jq -c '.exclude' diataxis.config.json
```

You should see:

```
["**/testdata/**","**/*_test.go","**/node_modules/**","diataxis/**"]
```

Checkpoint: The exclude list ends with `diataxis/**`. The config is validated against a schema on every load, so a typo here fails the next command with exit code 2 and the offending JSON pointer.

## Step 8: Produce the page inventory, which reads your sources, symbols, context files and git history and writes one diffable plan file.

```text
./diataxis/bin/diataxis plan
```

You should see:

```
plan: gathering sources, symbol inventory and context...
plan: wrote 5 pages to .diataxis/plan.json (explanation: 1, howto: 2, reference: 1, tutorial: 1)
```

Checkpoint: `.diataxis/plan.json` now exists. Your page count and the split across modes differ from the numbers above, because the model decides which pages this repository needs. This command writes no prose.

## Step 9: Read the plan before you spend money on it, since `generate` writes exactly the pages listed here and nothing else.

```text
jq -r '.pages[] | "\(.mode)\t\(.slug)\t\(.rationale)"' .diataxis/plan.json
```

You should see:

```
reference	reference/greeter	derived mechanically from the symbol inventory
tutorial	tutorials/greet-someone-in-french	one beginner journey ending in a working greeting
howto	how-to/add-a-language	single goal: extend GREETINGS with a new language
howto	how-to/handle-an-unknown-language-code	single goal: react to the ValueError
explanation	explanation/why-greetings-live-in-a-dictionary	the design choice behind the lookup table
```

Checkpoint: Each line names one page, its mode and why the plan wants it. The `reference/greeter` entry carries the rationale "derived mechanically from the symbol inventory": the harness derives reference pages from the symbol inventory itself, one page per module, rather than asking the model to invent them. Your slugs and rationales differ.

## Step 10: Generate the pages, capping this run at five dollars so that a mistake cannot spend more; the harness calls the model once per page, so this step takes several minutes.

```text
./diataxis/bin/diataxis generate --budget-usd 5
```

You should see:

```
[1/5] reference/greeter (reference)
[2/5] tutorials/greet-someone-in-french (tutorial)
  verifying tutorial tutorials/greet-someone-in-french (executing its code blocks)...
[3/5] how-to/add-a-language (howto)
[4/5] how-to/handle-an-unknown-language-code (howto)
[5/5] explanation/why-greetings-live-in-a-dictionary (explanation)
generate: 5 ok, 0 failed, 0 split, 0 skipped (spent $1.42 this run)
```

Checkpoint: The final line reports every page as ok and prints what the run spent. The tutorial page takes longest because the harness executes its fenced code blocks in a throwaway directory and repairs the page if a block fails. Each generated page also lands in `.diataxis/manifest.json`, so a run that stops on budget resumes where it left off.

## Step 11: Read one of the pages you produced, and confirm that the tutorial page records its verification result.

```text
head -12 docs/reference/greeter.md
grep -h 'verified:' docs/tutorials/*.md
```

You should see:

```
---
title: "greeter reference"
slug: reference/greeter
mode: diataxis
mode: reference
generated_by: diataxis
generated_at: 2026-07-30T12:04:11Z
frozen: false
---

# greeter reference

Greetings for a name in a chosen language.
verified: true
```

Checkpoint: Every page is plain Markdown with YAML frontmatter that records its slug, mode and generation time, and tutorial pages add `verified: true` once their code blocks ran successfully. The prose is generated; this layout is not, because the harness renders it through a shell template and writes the file itself.

## Step 12: See what the run cost, per mode, from the manifest.

```text
./diataxis/bin/diataxis cost
```

You should see:

```
total: $1.42 across 5 pages
  explanation: 1 pages, $0.51
  howto: 2 pages, $0.28
  reference: 1 pages, $0.08
  tutorial: 1 pages, $0.55
```

Checkpoint: Explanation and tutorial pages dominate the bill, because those two modes route to the most capable model while how-to and reference pages route to a cheaper one.

## Step 13: Run the CI gate, which writes nothing and fails when any page is stale, cites a source that moved, or is an unverified tutorial.

```text
./diataxis/bin/diataxis check
echo $?
```

You should see:

```
check: 0 findings, 0 stale, 0 audit failures, 0 unverified tutorials
0
```

Checkpoint: The exit status is 0, which is what a CI job reads. You may also see one or more `warning:` lines for an exported symbol that has no reference entry; the status stays 0 because only findings at error severity fail the gate. A stale page exits 31 and an unverified tutorial exits 32.

## Step 14: Commit the documentation, the plan and the manifest, so the next run knows what it already generated.

```text
git add docs .diataxis diataxis.config.json
git commit -q -m "Generate the initial documentation set"
git log --oneline
```

You should see:

```
4b8e0d1 Generate the initial documentation set
7a3d92f Vendor the diataxis documentation harness
9f1c2ab Initial commit
```

Checkpoint: You are done. The repository holds a vendored harness, a config, a reviewed plan, a docs/ tree of generated pages, and a committed manifest. Edit `src/greeter/greet.py` and run `check` again to watch the affected page turn stale.

## Next steps

- [how-to/review-and-edit-the-page-plan](../how-to/review-and-edit-the-page-plan.md)
- [how-to/control-spend-with-a-budget](../how-to/control-spend-with-a-budget.md)
- [how-to/gate-pull-requests-on-documentation-freshness](../how-to/gate-pull-requests-on-documentation-freshness.md)
- [explanation/why-the-harness-owns-the-filesystem](../explanation/why-the-harness-owns-the-filesystem.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)

