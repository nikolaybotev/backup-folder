# intent.md — Test webhook helper

| | |
|---|---|
| Author | Maintainer |
| Captured | 2026-10-31 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [Drop Box watcher](../drop-box-watcher/intent.md) |

## Problem

The drop-box-watcher sends routine webhooks when files become ready. There is no supported way in this repo to fire one manual empty POST with the same URL, authorization header, and JSON shape as the watcher, without putting the routine key on the command line or in shell history.

## Proposed outcome

A POSIX `sh` helper under `scripts/` reads `url` and `key` from the `[webhook]` table in the watcher config, passes them to `curl` through a config file on standard input (`curl -K -`), and POSTs `{"source":"manual","files":[]}`. Operators can sanity-check connectivity after editing config. CI proves the helper with a fake config, a dummy key, and a local listener. The helper is not a release asset.

## Affected users and systems

- **Users:** the person who maintains the watcher config and routine webhook on a Mac.
- **Systems:** this repo. The new script, its integration test, and one line in the watcher-facing docs. Not a live config, not a live key, and not the deployment Mac from CI or agents.

## Constraints and principles

- Keep POSIX `sh`. Do not require bash-only features beyond what the starting sketch already uses.
- The routine key must not appear in `argv` and must not be printed by the helper.
- Default config path stays `~/.config/drop-box-watcher/config.toml`. An optional argument overrides it.
- Fail closed before POST when the config file, the `[webhook]` section, or either of `url` or `key` is missing.
- Tests never read a real config and never use a real key.
- Docs stay generic. Prose about the repo says "this repo". No hostnames, machine names, personal names, or setup paths beyond existing placeholders.
- Do not change product Swift code in the design pull request. Do not merge or install anything in the design phase.

## Open questions (carried into spec.md)

1. Which human-facing doc gets the one-line mention (README watcher section vs setup checklist)?
2. Should the integration test run on the `linux` job only, or on both required jobs?

## Original prompt (verbatim)

```
Write a design pull request for a small helper in this repo. Docs only: intent/test-webhook/intent.md, spec.md, and plan.md. Link it to the existing intent chain if one is the natural parent (the watcher). Match the header style of intent/one-backup-job/ and the ai-native-sdlc templates. Status stays Draft. Do not change product code. Do not merge. Do not install anything.

This was approved on 2026-10-31. One later build pull request is enough unless the plan finds a real split. This pull request is the spec only.

Goal: add scripts/test-webhook.sh. It sends one manual empty POST, body {"source":"manual","files":[]}, to the drop-box-watcher webhook. Read url and key from the [webhook] section. Pass them to curl on stdin with -K - so the key never appears in argv and is never printed.

Starting point, which the spec may tighten but must not weaken:

#!/bin/sh
CFG=~/.config/drop-box-watcher/config.toml
val() { awk -F'"' -v k="$1" '/^[[:space:]]*\[/{s=($0 ~ /^[[:space:]]*\[webhook\]/)} s && $1 ~ "^[[:space:]]*"k"[[:space:]]*=" {print $2; exit}' "$CFG"; }
printf 'url = "%s"\nheader = "Authorization: Bearer %s"\n' "$(val url)" "$(val key)" | curl -sS -K - -X POST -H 'Content-Type: application/json' -d '{"source":"manual","files":[]}' -w '\nHTTP %{http_code}\n'

Required tweaks:
1. Optional config-path argument. Default remains ~/.config/drop-box-watcher/config.toml.
2. Exit nonzero with a clear message if the config file is missing, the [webhook] section is missing, or url or key is missing. Do not POST an empty URL.

Keep POSIX sh. Tests use a fake config, a dummy key, and a local listener. Never a real config, never a real key. Add one line to the watcher docs describing the helper. Docs stay generic: no hostnames, machine names, personal names, or setup details. Prose says "this repo".

Keep the script out of release artifacts. Read the release workflow and record what a merge to main does to the version. Do not add a release label. Do not change the version scheme in this pull request. Do not invent a skip if none exists.

Public text stays generic. Under Original prompt, record the product request without person names or machine names. The owner's name stays only in LICENSE. No Co-authored-by trailer. Conventional commit. Open the PR against main.
```
