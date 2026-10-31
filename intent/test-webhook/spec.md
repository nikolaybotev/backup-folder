# spec.md — Test webhook helper

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-31) |
| Status | Draft 1 |
| Stage | 2 · Design |

## 1. Summary

`scripts/test-webhook.sh` is a POSIX `sh` helper for operators. It reads `url` and `key` from the `[webhook]` table in the drop-box-watcher TOML config, builds a `curl` config on standard input, and POSTs one manual nudge: `{"source":"manual","files":[]}`. The routine key is passed only through `curl -K -` stdin lines, not through `argv`, and the script does not print the key. An optional first argument selects the config file; the default is `~/.config/drop-box-watcher/config.toml`. Missing file, missing section, or missing `url` or `key` exits non-zero with a clear message and does not POST.

`tests/test-webhook.sh` is an integration test: fake config, dummy key, loopback HTTP listener. It runs in CI on both required jobs. The README `drop-box-watcher` section gains one line pointing at the helper. The helper is not uploaded by job `publish`.

## 2. Goals and non-goals

**Goals**

- G1. One manual POST with the same JSON shape the watcher uses for an empty file list.
- G2. Read `url` and `key` only from `[webhook]` in the chosen config file.
- G3. Pass URL and `Authorization: Bearer …` to `curl` via stdin config (`curl -K -`). The key never appears in `argv` and is never echoed by the script.
- G4. Optional config path argument with the existing default path when omitted.
- G5. Fail closed with stderr messages before POST when the config file is unreadable or missing, when no `[webhook]` section contributes values, or when `url` or `key` is empty after parsing.
- G6. Integration test with fake config, dummy key, and local listener; never a real config or real key.
- G7. Document the helper in one line in the watcher-facing README section.

**Non-goals**

- Do not change Swift watcher code, webhook actor behavior, or config schema.
- Do not add the script to GitHub release assets, `scripts/install-tools.sh`, or `pins.txt.example`.
- Do not read or write a live home config, pin file, or anything under a home `Backups` directory from CI or agent work.
- Do not add a `release:minor` or `release:major` label in the build pull request.
- Do not change `scripts/release-version.sh`, the version scheme, or job `publish` beyond what already ships both binaries.
- Do not run `launchctl` or install the watcher from this intent.
- Do not type-check or link product Swift on Linux beyond existing jobs.

**Release phasing.** The helper and its test ship in one build pull request unless [plan.md](plan.md) records a split. Untagged requirements belong to that build.

## 3. Principles

- P1. Secrets on `argv` are forbidden (CWE-214). stdin config for `curl` is the chosen transport for URL and bearer token.
- P2. An empty webhook URL must not be POSTed.
- P3. Operator docs say "this repo". Human-facing docs do not restate that exit 0 means success. Agent-facing files may keep explicit expectations such as "(healthy: exit 0)".
- P4. Tests are integration: real `sh`, real `curl`, real `awk`, loopback listener; no real routine key.
- P5. Job `publish` continues to attach only `backup-folder`, `drop-box-watcher`, and `SHA256SUMS`. This script stays out of that list without inventing a new skip mechanism.

## 4. Users and scenarios

- After editing watcher config on a Mac, the operator runs the helper (default path) and reads the printed HTTP status line.
- The operator points the helper at a copy of the example config under `/tmp` while debugging parsing, without touching the live file.
- CI runs the integration test on Ubuntu and macOS with a temp config and a dummy key string reserved for tests.
- A merge of the build pull request to `main` without a release label bumps the patch version and may publish a release that still contains only the two binaries and checksums—not this script.

## 5. Functional requirements

1. **Path:** `scripts/test-webhook.sh`. Shebang `#!/bin/sh`. Executable bit set in git.
2. **Usage:** `scripts/test-webhook.sh` or `scripts/test-webhook.sh /abs/path/to/config.toml`. When the argument is present it is the config path. When absent, use `~/.config/drop-box-watcher/config.toml` (tilde expanded by the shell when assigning the default).
3. **Parsing:** Inside the selected file only, detect the `[webhook]` table and read basic-string values for keys `url` and `key` using the same `awk` field model as the approved starting sketch (`-F'"'`, toggle section on `^[[:space:]]*[webhook]`, match `^[[:space:]]*key[[:space:]]*=`). The spec may tighten quoting or whitespace rules but must still accept the example config shape in `drop-box-watcher.example.toml`. Do not parse other tables for webhook credentials.
4. **Validation (before curl):**
   - Config path not a readable file → message includes that the config file is missing or unreadable → exit 2.
   - No `[webhook]` section or neither key yields a value → message includes `[webhook]` → exit 2.
   - Empty `url` or empty `key` after parse → message names the missing field → exit 2.
   - Do not invoke `curl` when `url` is empty.
5. **POST:** Pipe to `curl -sS -K - -X POST -H 'Content-Type: application/json' -d '{"source":"manual","files":[]}' -w '\nHTTP %{http_code}\n'` where stdin lines are `url = "<parsed url>"` and `header = "Authorization: Bearer <parsed key>"`. Use command substitution for parsed values when building those lines; do not pass the key as a separate curl argument. Stdout is curl output plus the HTTP status trailer. The script must not print the key to stdout or stderr (checked 2026-10-31: `curl -K -` reads secrets from the config stream; the script body must not `echo` the key).
6. **Exit status:** Propagate curl’s exit code on transport failure. Validation failures use exit 2. Successful HTTP responses still print the status line; non-2xx HTTP codes do not need a distinct exit code unless curl already fails—do not add HTTP-code-based exit logic beyond curl’s behavior.
7. **Integration test:** `tests/test-webhook.sh`. Creates a temp dir, writes a minimal valid watcher config with `[webhook]` pointing at `http://127.0.0.1:<ephemeral-port>/` and a fixed dummy key string `test-webhook-integration-key` (not a real secret). Starts a short-lived Python 3 loopback handler (same approach as `tests/macos-watcher.sh`) that records the `Authorization` header and JSON body, runs `scripts/test-webhook.sh` against the temp config, asserts HTTP 200, bearer header, and body `{"source":"manual","files":[]}`. Asserts stderr/stdout from the helper do not contain the dummy key. Includes at least one case where a missing config file exits non-zero. Healthy line: `test-webhook: OK`.
8. **CI:** Add a step on job `linux` and job `macos` in `.github/workflows/test.yml` that runs `bash tests/test-webhook.sh`. Do not change `timeout-minutes` or required job names.
9. **Docs:** Add exactly one sentence to the README section `## drop-box-watcher` naming `scripts/test-webhook.sh` and that it sends one manual empty POST using values from the watcher config. No hostname, no personal path, no 1Password instruction in that sentence.
10. **AGENTS.md:** In the build phase, add a bullet under Commands for `bash tests/test-webhook.sh` with the healthy line, and mention the helper script path for operators on macOS. Do not edit `AGENTS.md` in the design pull request.
11. **Release artifacts:** Job `publish` in `.github/workflows/release.yml` uploads only `backup-folder`, `drop-box-watcher`, and `SHA256SUMS`. This intent does not add the helper to that `files:` list and does not add a workflow skip—the script was never part of the release layout.

## 6. Acceptance criteria

| ID | Criterion | Check |
|---|---|---|
| AC1 | Helper exists, POSIX `sh`, optional config arg, curl `-K -`, manual JSON body | Review `scripts/test-webhook.sh` |
| AC2 | Fail closed on missing file, section, url, or key | Integration test negative case |
| AC3 | Key not in argv and not printed | Integration test grep on helper output; review script |
| AC4 | Integration test uses fake config and dummy key only | Review `tests/test-webhook.sh` |
| AC5 | README gains one generic line | Review README diff |
| AC6 | Required checks green after build | `macos` and `linux` jobs run `bash tests/test-webhook.sh` |
| AC7 | Release layout unchanged | `tests/release-workflow.sh` still passes; release `files:` still lists two binaries and checksums only |

## 7. Design decisions

**D1 — Parent intent.** This helper supports the drop-box-watcher webhook configured in [drop-box-watcher](../drop-box-watcher/intent.md). It reuses the same `[webhook]` keys as FR3 there, not backup-job config.

**D2 — `curl -K -` for the bearer token.** Command-line arguments would expose the routine key in `ps`. Environment variables would still appear in the process environment. Feeding a curl config on stdin keeps the key off `argv` and matches the approved starting sketch. Rejected: `-H "Authorization: Bearer $key"` on the command line.

**D3 — `awk` basic-string scrape.** Full TOML parsing in `sh` is out of scope. The starting `val()` function is retained as the minimum parser, tightened only for clearer errors and optional path. Rejected: shelling out to the Swift config parser (would drag Darwin or a new Linux compile of watcher code into a helper).

**D4 — README one-liner, not setup.md.** The helper is a developer/operator convenience tied to the watcher product description already in README. Setup checklist stays install-focused. Checked 2026-10-31 against [intent.md](intent.md) open question 1.

**D5 — Test on both CI jobs.** The script is `sh` plus `curl` and Python 3; both runners provide them. Running on `linux` and `macos` catches path and `curl` behavior differences. Checked 2026-10-31 against open question 2.

**D6 — Version on merge to `main`.** Push to `main` runs job `publish`. `scripts/release-version.sh` prints `tag vMAJOR.MINOR.PATCH` when HEAD has no semver tag yet: patch increments by default; `release:minor` or `release:major` on the merged pull request bumps minor or major instead. The job may push that lightweight tag and publish a GitHub release whose assets remain the two signed binaries and `SHA256SUMS`. If HEAD already points at a semver tag, the script prints `noop` and the job reuses that tag. A later step skips upload when `gh release view` finds the tag already published. This intent does not add a release label, so a typical docs-or-script merge bumps patch only. Checked 2026-10-31 against `.github/workflows/release.yml` and `scripts/release-version.sh`.

## 8. Open questions

None. D4 and D5 close the items carried from [intent.md](intent.md).
