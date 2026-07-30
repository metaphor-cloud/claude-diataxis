---
title: "Reproducibility and bare mode"
slug: explanation/reproducibility-and-bare-mode
mode: explanation
generated_by: diataxis
generated_at: 2026-07-29T21:42:03Z
frozen: false
---

# Reproducibility and bare mode

`--bare` is the harness's only real defence against a machine's local Claude configuration leaking into your documentation, and because bare mode also disables keychain and OAuth reads, choosing reproducibility is the same decision as choosing how you authenticate.

## The coupling at the centre of this page

Two properties of the `claude` CLI's `--bare` flag are, from the harness's point of view, welded together.

The first property is the one the harness wants. Bare mode skips hooks, skills, plugins, Model Context Protocol (MCP) servers, `CLAUDE.md` files and automatic memory. Without it, the prose you get depends on whatever happens to live in the invoking machine's `~/.claude` directory. A teammate with an opinionated global `CLAUDE.md` and a `PostToolUse` hook does not just get slightly different wording; they get a different context window, and therefore a different page, from the same repository at the same commit. For a tool whose whole premise is that documentation is a reproducible function of source code, that is not a cosmetic problem.

The second property is the price. Bare mode also skips OAuth and keychain reads. The credentials that `claude auth login` puts in your operating system keychain are exactly the credentials bare mode refuses to look for. So bare mode works only when the credential arrives through the environment (`ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`) or through an `apiKeyHelper` in a settings file passed with `--settings`.

Nothing in the harness can decouple these. `resolve_bare` is the code that admits it, and its comment says so plainly rather than hiding the constraint behind a config key.

## Capability and use are two different facts

The config key `bare` accepts `"auto"`, `true` or `false`, and the schema enumerates exactly those three values. `resolve_bare` turns that key plus the detected authentication method into two exported facts, not one: whether the run *could* run bare (`DIATAXIS_BARE_CAPABLE`) and whether it *will* (`DIATAXIS_USE_BARE`).

Capability comes from the authentication method that `check_auth` recorded. An API key or OAuth token in the environment is bare-capable. A subscription login read from the keychain is not. A configured `settings_file` is treated as bare-capable on the operator's word, on the theory that it might carry an `apiKeyHelper` and the harness has no cheap way to know whether that helper works.

Use then depends on the config key. Under `false`, bare mode is off regardless. Under `true`, an authentication method that cannot support it is a hard failure with exit code 16 rather than a silent downgrade. Under the default `"auto"`, use simply follows capability, and the interesting case is the one where capability is absent: the run continues without `--bare` and emits a single warning that local `CLAUDE.md`, hooks and plugins are in context, so output may not match continuous integration (CI).

That warning is the design in miniature. A local `generate` run on a subscription login is a legitimate and common thing to do, and refusing it outright would make the tool unusable for the person most likely to be iterating on the plan. But the operator needs to know that the artifact they are about to commit was produced under conditions their CI cannot reproduce. So the harness degrades, and it tells you.

Because `resolve_bare` runs inside `preflight`, which every subcommand calls, that resolution and that warning are not confined to `doctor`. `doctor` differs only in also reporting the outcome as a machine-readable `bare_capable` field, which is the thing a CI setup step should assert on before it spends any money.

## Why check refuses to run without bare-capable auth

`cmd_check` calls `require_bare_capable` immediately after `preflight`, and dies with exit 16 if the credentials cannot support bare mode. Look closely at which of the two facts it tests: capability, not use.

That choice reads oddly at first. `check` writes nothing, and by default it makes no model calls at all, computing staleness, broken citations, orphans and unverified tutorials from local hashes. If `check` is not calling the model, why does it care how the model would have been called?

Because the gate is not about `check`'s own behaviour. It is a statement about the repository's reproducibility posture. `check` is the gate that decides whether the committed documentation is trustworthy, and its verdict is only meaningful if the documentation it is judging could have been produced in a reproducible way. Refusing to run at all on a machine that cannot produce reproducible output is a blunter instrument than auditing each page's provenance, but it needs no new manifest fields and it cannot be quietly ignored the way a warning can. The bats suite pins the behaviour: a plain `check` against the stub's default subscription auth exits 16, and the same `check` with an OAuth token in the environment proceeds to real findings.

Testing capability rather than use also means a repository that deliberately sets `"bare": false` and exports an API key still passes. That is intentional. What the gate rejects is the *implicit* case, where nobody decided anything and the run would inherit a machine's local configuration by accident. An operator who wrote `false` into a committed config file has made a recorded decision, and the harness does not second-guess recorded decisions.

When `audit.model_audit_in_check` is on and `check` does make model calls, the gate stops being merely symbolic and starts governing the calls it actually makes.

## What guards the non-bare path

Since the harness accepts that many runs will not be bare, the interesting question is what protection survives.

The strongest surviving guard is not a bare mode feature at all. Every generation call passes `--strict-mcp-config` with no `--mcp-config`, which loads zero MCP servers whether or not `--bare` is present. The README records this as a decision found by dogfooding: a policy-blocked MCP server in a user's configuration failed a generation that never needed MCP. Since the harness allows only `Read`, `Grep` and `Glob`, ambient MCP servers are noise at best and a failed run at worst, and this flag removes that whole class of failure from the non-bare path.

The rest of the call is pinned by construction rather than by isolation. `claude_run` fixes the model, the effort, the system prompt file, the tool allowlist, the permission mode, the output format and the JSON schema on every invocation. What `--bare` adds on top is protection against context you did not ask for: prompt text from a `CLAUDE.md`, behaviour changes from a hook, tools from a plugin. Those are precisely the things the harness cannot pin from the outside, which is why `--bare` is the flag that matters and why its absence is worth a warning.

Note that `--settings` is applied independently of bare mode. A settings file is passed on every call when configured, so a settings file can supply credentials to a bare run without being the reason the run is bare.

## Where the harness contradicts its own dependency

One deliberate deviation deserves naming, because it is the most likely source of a confusing failure.

The installed CLI's `--bare` help text describes the supported credentials as strictly `ANTHROPIC_API_KEY` or an `apiKeyHelper` supplied through `--settings`. `resolve_bare` additionally treats `CLAUDE_CODE_OAUTH_TOKEN` as bare-capable.

The harness chose the broader contract because `claude setup-token` is the documented way to produce a long-lived credential for CI, and a reproducibility gate that rejects the credential the vendor tells you to use in CI is a gate nobody will keep. The cost is that the harness's model of bare mode is now slightly ahead of one version of its dependency's documentation, and if your CLI rejects the token in bare mode you have to fall back to `"bare": false` or an API key. That escape hatch exists precisely because this deviation might be wrong on some version.

A smaller deviation sits alongside it: `resolve_bare` marks a configured `settings_file` bare-capable without reading it. That trusts the operator, and it produces a worse error than it needs to when the trust is misplaced. A settings file with no `apiKeyHelper` passes `resolve_bare`, passes `require_bare_capable`, and then fails at the first model call with a message about authentication rather than about configuration.

## The reproducibility this does not buy

Be clear about the limits, because `--bare` is easy to over-read as a determinism guarantee.

Bare mode removes local configuration from the context window. It does not make the model deterministic. Two bare runs over an unchanged repository can produce different prose, which is exactly why the harness leans on the manifest instead: `compute_inputs_hash` covers the source contents, the system prompt, the task template, the schema, the config's model block and the plan entry, and an unchanged hash means no call happens at all. Reproducibility in practice comes from *not regenerating*, and `--bare` is what makes the decision to regenerate depend on the repository rather than on the machine.

That hash also reveals the gap in the current design: it records nothing about bare mode or the authentication method. A page generated on a laptop with a global `CLAUDE.md` in context produces a manifest entry indistinguishable from one generated bare in CI. `check` can tell you that inputs changed, and it can tell you that a different model answered than the one configured, but it cannot tell you that a page was produced under non-reproducible conditions. Today the only signal is a warning on stderr at generation time, which nobody reads six weeks later in a code review.

A related asymmetry: the merged system prompt that `claude_system_prompt_file` writes includes the configured voice conventions, while `compute_inputs_hash` hashes the pristine prompt file from the harness root. Changing `voice.style_guide` therefore does not make pages stale. That belongs to the staleness contract rather than to bare mode, but it is the same species of gap: a real input to the call that the hash does not see.

## Tradeoffs

| Decision | Chose | Rejected | Because |
| --- | --- | --- | --- |
| What to do when the authentication method cannot support bare mode under the default `"auto"` setting | Run without `--bare` and emit a one-line warning that local `CLAUDE.md`, hooks and plugins are in context | Fail the run, the way `"bare": true` does | A local `generate` on a subscription login is the normal path for the person iterating on the plan, and refusing it would make the tool unusable for them. The operator still needs to know the artifact was produced under conditions CI cannot reproduce, so the harness degrades loudly rather than silently. |
| Which flag the `check` gate tests | `DIATAXIS_BARE_CAPABLE`, the capability | `DIATAXIS_USE_BARE`, what the run will actually do | A repository that sets `"bare": false` has made an explicit, committed decision, and the gate should not override recorded operator intent. What the gate exists to catch is the implicit case, where nobody chose and the run would inherit local machine state by accident. |
| How much protection the non-bare path keeps | Pass `--strict-mcp-config` with no `--mcp-config` on every call, independently of bare mode | Treating MCP isolation as something `--bare` alone provides | Dogfooding found a policy-blocked MCP server failing a generation that only ever needed Read, Grep and Glob. Removing ambient MCP servers unconditionally deletes that failure class from the path that has the least protection. |
| Whether `CLAUDE_CODE_OAUTH_TOKEN` counts as bare-capable | Treat it as bare-capable, contradicting the installed CLI's `--bare` help text | Following the help text and accepting only `ANTHROPIC_API_KEY` or an `apiKeyHelper` | `claude setup-token` is the documented way to mint a long-lived CI credential, and a reproducibility gate that rejects the vendor's own CI credential is a gate teams will disable. `"bare": false` remains available if a CLI version rejects the token. |
| Whether to validate a configured `settings_file` before marking it bare-capable | Trust the operator without reading the file | Probing the file for an `apiKeyHelper` key | The harness cannot tell whether a helper actually works without executing it, so any check would be partial. The cost of the shortcut is a worse error message: a settings file with no helper fails later, inside the first model call, as an authentication error rather than a configuration error. |
| Where reproducibility ultimately comes from | Skipping regeneration on an unchanged `inputs_hash` | Relying on bare mode to make model output repeatable | The model is not deterministic even under identical context. `--bare` earns its place by making the *decision to regenerate* depend on the repository rather than the machine, not by making a given call repeatable. |

## Open questions

- Should `inputs_hash`, or a separate manifest field, record whether a page was generated in bare mode and under which authentication method? Today `check` can detect changed inputs and model divergence, but cannot tell that a page was produced with a laptop's `CLAUDE.md` in context.
- Should `resolve_bare` probe a configured `settings_file` for an `apiKeyHelper` key, so a misconfigured file fails at preflight with exit 16 instead of inside the first model call with an authentication error?
- Is `check`'s all-or-nothing exit 16 the right shape, given that `check` makes no model calls by default? A per-page provenance check would let a repository with mixed history be gated page by page instead of refused wholesale.
- Does the deviation on `CLAUDE_CODE_OAUTH_TOKEN` need a version test rather than a documented note? The harness currently pins a minimum CLI version but does not verify that the installed version accepts the token in bare mode.
- Should the merged system prompt, which carries the configured voice conventions, feed `compute_inputs_hash` instead of the pristine prompt file? Changing `voice.style_guide` is a real change to the call that no page currently becomes stale for.

## Related

- [how-to/authenticate-runs-for-continuous-integration](../how-to/authenticate-runs-for-continuous-integration.md)
- [how-to/gate-pull-requests-on-documentation-freshness](../how-to/gate-pull-requests-on-documentation-freshness.md)
- [how-to/diagnose-environment-and-authentication-failures](../how-to/diagnose-environment-and-authentication-failures.md)
- [explanation/audit-versus-check](../explanation/audit-versus-check.md)
- [explanation/staleness-idempotency-and-the-manifest](../explanation/staleness-idempotency-and-the-manifest.md)
- [explanation/why-the-harness-owns-the-filesystem](../explanation/why-the-harness-owns-the-filesystem.md)
- [explanation/model-routing-and-cost](../explanation/model-routing-and-cost.md)
- [how-to/inspect-a-run-without-calling-the-model](../how-to/inspect-a-run-without-calling-the-model.md)

