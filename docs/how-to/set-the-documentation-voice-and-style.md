---
title: "Set the documentation voice and style"
slug: how-to/set-the-documentation-voice-and-style
mode: howto
generated_by: diataxis
generated_at: 2026-07-29T21:44:10Z
frozen: false
---

# Set the documentation voice and style

Configure the style guide, grammatical person, and any project-specific writing conventions the harness applies to every generated page.

## Before you start

- how-to/vendor-the-harness-into-a-repository
- tutorials/generate-your-first-documentation-set

## Steps

1. Open `diataxis.config.json` at the repository root and find the `voice` block. If the key is absent, the harness applies its defaults: Google style, second person, no extra instructions file.

   ```json
   "voice": {"style_guide": "google", "person": "second", "extra_instructions_file": null}
   ```

   Expected result: The `voice` key exists in the config with three sub-keys: `style_guide`, `person`, and `extra_instructions_file`.

2. Set `style_guide` to the guide the model should follow. The harness accepts `google` or `microsoft`.

   ```json
   "voice": {"style_guide": "microsoft", "person": "second", "extra_instructions_file": null}
   ```

   Expected result: `jq -e '.voice.style_guide' diataxis.config.json` prints the value you set.

3. Set `person` to the grammatical person the prose should use, for example `second` for "you" or `third` for "the user".

   ```json
   "voice": {"style_guide": "google", "person": "third", "extra_instructions_file": null}
   ```

   Expected result: The config still validates: run `diataxis/bin/diataxis doctor` and confirm it exits 0, or run any subcommand and confirm it does not exit with code 2 (config invalid).

4. To add project-specific writing rules beyond the style guide (a terminology list, a banned-words list, a product name capitalization rule), write them as Markdown in a file inside the repository and point `extra_instructions_file` at its path, relative to the repository root.

   ```json
   "voice": {"style_guide": "google", "person": "second", "extra_instructions_file": "docs/voice-extra.md"}
   ```

   Expected result: The file `docs/voice-extra.md` exists at the path you referenced.

5. Regenerate a page and inspect the merged system prompt the harness sent to the model, to confirm your instructions were appended.

   ```sh
   diataxis/bin/diataxis generate --page docs/how-to/some-page.md --dry-run
   ```

   Expected result: The dry-run argv includes `--append-system-prompt-file` pointing at a file under the run's temp directory; opening that file shows the base system prompt for the mode, followed by the `## Voice and style` block with your `style_guide` and `person`, followed by the verbatim contents of `extra_instructions_file` if you set one.

## Verify it worked

Run `diataxis/bin/diataxis generate --page <any-planned-page> --dry-run` and open the file passed to `--append-system-prompt-file`. It should end with a `## Voice and style` section naming your configured style guide and person, followed by the contents of `extra_instructions_file` (if set) verbatim. A real (non-dry-run) generation of that page should read naturally in your chosen person and follow any rules from the extra file.

## Related

- [how-to/regenerate-a-single-page](../how-to/regenerate-a-single-page.md)
- [how-to/protect-hand-written-pages-from-regeneration](../how-to/protect-hand-written-pages-from-regeneration.md)
- [explanation/the-diataxis-mode-contract](../explanation/the-diataxis-mode-contract.md)

