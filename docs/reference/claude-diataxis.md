---
title: "claude-diataxis reference"
slug: reference/claude-diataxis
mode: reference
generated_by: diataxis
generated_at: 2026-07-29T21:18:14Z
frozen: false
---

# claude-diataxis reference

Reference for install.sh, the POSIX shell script that vendors the diataxis harness into a target repository and writes a starter configuration file.

## `install.sh`

*cli_flag*

```
install.sh [target-repo-dir]
```

Copies the harness directories (bin, lib, prompts, schemas, share) into <target-repo-dir>/diataxis, makes bin/diataxis executable, and writes a starter diataxis.config.json if one does not already exist.

| Parameter | Type | Description |
| --- | --- | --- |
| `target-repo-dir` (optional) | `string` | Path to the repository to vendor the harness into. Defaults to . (the current directory) when omitted. |

Returns: Exit status 0 on success. Exit status 1 (via die) on any precondition failure or copy failure.

Raises:
- target directory not found: <target> - TARGET does not exist as a directory
- git is required - the git command is not on PATH
- not running from a harness checkout and DIATAXIS_REPO_URL is not set - install.sh is not co-located with an executable bin/diataxis and DIATAXIS_REPO_URL is unset
- could not clone <url> - git clone --depth 1 of DIATAXIS_REPO_URL failed
- <dest> already exists; remove it or update via git subtree/submodule instead - $TARGET/diataxis already exists

Source: `install.sh` (lines 1-63)

## `TARGET`

*variable*

```
TARGET=${1:-.}
```

Target repository directory, taken from the first positional argument or defaulting to the current directory.

Source: `install.sh` (lines 15)

## `DEST`

*variable*

```
DEST="$TARGET/diataxis"
```

Destination directory under TARGET into which the harness is vendored.

Source: `install.sh` (lines 16)

## `DIATAXIS_REPO_URL`

*config_key*

```
DIATAXIS_REPO_URL=<git-url>
```

Environment variable giving the git URL to clone the harness from when install.sh is not itself run from a harness checkout (for example, when piped through curl). Required in that case; otherwise unused.

Source: `install.sh` (lines 32-38)

## `self_dir`

*variable*

```
self_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || self_dir=''
```

Absolute directory containing install.sh itself, resolved so the script can detect whether it is running from a harness checkout. Empty string if resolution fails.

Source: `install.sh` (lines 27)

## `src`

*variable*

```
src="$self_dir" | src=$(mktemp -d ...)
```

Source directory the harness files are copied from: self_dir when install.sh is run from a checkout containing an executable bin/diataxis, otherwise a temporary directory populated by cloning DIATAXIS_REPO_URL. The temporary directory is removed on exit via a trap.

Source: `install.sh` (lines 29-38)

## `die`

*function*

```
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
```

Prints its arguments as an 'error: ' message to standard error and exits the script with status 1.

| Parameter | Type | Description |
| --- | --- | --- |
| `$*` | `string` | Error message text to report. |

Returns: Does not return; terminates the script with exit status 1.

Source: `install.sh` (lines 18-21)

