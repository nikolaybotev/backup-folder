# plan.md — Mac setup decisions

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 2 |
| Status | Draft 2 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it. The only allowed edit under `intent/` during Phase 0 is an appended build note on this file. Do not edit any other `intent/` folder, and do not rewrite the spec.

The pull request that adds this folder does not start Phase 0. Phase 0 starts only after this pull request has been reviewed and its commits are on `main`. It is one commit on a new branch from that `main`, one pull request, opened ready for review, with a conventional commit. Required checks stay `macos` and `linux`. Phase 0 does not merge that pull request. The session that only writes this folder does not merge the spec pull request. Merging the spec pull request publishes the next patch tag. That is existing behavior (spec AC7). Neither pull request adds a release label or pushes a tag by hand.

## Stops

None. Do not merge either pull request from the work described here. Publishing a patch tag from a later merge of the spec pull request is not a stop (spec D9).

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | Spec diff is only `intent/mac-setup-decisions/` | this pull request, not Phase 0 |
| AC2 | `bash tests/release-workflow.sh`; `release.yml` unchanged | 0 |
| AC3 | `test.yml` unchanged; `Signature=adhoc` twice | 0 |
| AC4 | `bash tests/setup-docs.sh`; sentence grep | 0 |
| AC5 | `bash tests/no-secrets.sh`; `git diff` path list | 0 |
| AC6 | No installer, pin, tag, or ruleset edit; pull request left unmerged | 0 |
| AC7 | No edit to `release.yml` or `scripts/release-version.sh` | this pull request, not Phase 0 |

## Phase 0 — Close the setup decisions

Files: `docs/setup.md`, `docs/restore.md`, `tests/release-workflow.sh`, `tests/setup-docs.sh`.

Do not edit: `.github/workflows/release.yml`, `.github/workflows/test.yml`, `.github/workflows/codeql.yml`, `scripts/`, `launchd/`, `AGENTS.md`, `README.md`, product sources, or any `intent/` folder other than an appended build note on this plan.

1. Do not edit `.github/workflows/release.yml`. The two `codesign --verify --strict` lines are already on `./backup-folder` and `"$watcher_bin"`, after `bash scripts/build.sh` and before the tag push. Do not add a second copy. Do not add `spctl`.
2. In `tests/release-workflow.sh`, keep every current `require_in_release` call and every current ban, including the `spctl` ban. Require the two exact strings `codesign --verify --strict ./backup-folder` and `codesign --verify --strict "$watcher_bin"`. Fail unless `codesign --verify --strict` occurs exactly twice in `release.yml`. Fail unless both lines are after `bash scripts/build.sh` and before `git push origin "refs/tags/`.
3. Do not edit `.github/workflows/test.yml`. Leave both `Signature=adhoc` checks.
4. Apply spec FR4 to `docs/setup.md` and spec FR5 to `docs/restore.md`. Keep 33 and 7 bullets. The restore paragraph names the existing LaunchAgent repeat and the `scripts/install-tools.sh` re-run. Do not add a self-hosted runner operation. Do not add a LaunchAgent. Do not add Xcode. Do not remove the `pinentry`, iStat Menus, or MacVim setup steps. Do not remove `Until then the script skips unpinned tools.` or `until the disk is unlocked.` The word "until" stays out of the notarization privacy bullet only. Do not add a rename sentence. Do not write `roger-bootstrap` into either doc.
5. Apply spec FR7 to `tests/setup-docs.sh`. Keep the current anchors and the counts. Add the new anchors. Fail on the FR6 strings.
6. Do not run `scripts/install-tools.sh` or `scripts/ensure-backup-dirs.sh`. Do not write a pin. Do not push a tag. Do not edit a ruleset. Do not run `launchctl`. Do not write `~/Backups`. Do not put a WireGuard key, address, or port in the diff. Install timing stays on hold.
7. Open one pull request, ready for review, conventional commit. Do not merge.

DoD: every command below exits 0. Run them from the repo root on the Phase 0 commit. That commit's parent is `main` after this folder is already on `main`. `git fetch` makes `origin/main` that commit. A branch that still contains the unmerged spec commits fails the parent check on purpose.

```
set -euo pipefail
bash tests/setup-docs.sh
bash tests/no-secrets.sh
bash tests/release-workflow.sh
test "$(grep -c 'Manual:\|Script:' docs/setup.md)" -eq 33
test "$(grep -c 'Manual:\|Script:' docs/restore.md)" -eq 7
grep -F 'Remote Login (SSH) is on' docs/setup.md
grep -F 'does not enable SSH' docs/setup.md
grep -F 'Low Power Mode off' docs/setup.md
grep -F 'Prevent automatic sleeping when the display is off' docs/setup.md
grep -F 'Wake for network access' docs/setup.md
grep -F 'After power failure' docs/setup.md
grep -F 'does not apply those settings' docs/setup.md
grep -F 'does not add a self-hosted runner' docs/setup.md
grep -F 'Install Cursor and sign in' docs/setup.md
grep -F 'Apple Developer ID notarization is out of scope' docs/setup.md
grep -F 'There is no plan to notarize' docs/setup.md
grep -F 'not operators of the machine' docs/setup.md
grep -F 'wireguard-go' docs/restore.md
grep -F 'does not install Xcode' docs/restore.md
grep -F 'GnuPG' docs/restore.md
grep -F 'Grok Bot' docs/restore.md
grep -F '1Password CLI' docs/restore.md
grep -F 'not operators of the machine' docs/restore.md
grep -F 'existing LaunchAgent repeat' docs/restore.md
grep -F '`scripts/install-tools.sh` re-run' docs/restore.md
grep -F 'Until then the script skips unpinned tools.' docs/setup.md
grep -F 'until the disk is unlocked.' docs/setup.md
if grep -F 'until Apple notarization' docs/setup.md docs/restore.md; then exit 1; fi
if grep -F 'roger-bootstrap' docs/setup.md docs/restore.md; then exit 1; fi
if grep -E '\(Q[2-6]\)|stays open|left unfinished|notarization is decided|until you name them' docs/setup.md docs/restore.md; then exit 1; fi
test "$(grep -c 'Signature=adhoc' .github/workflows/test.yml)" -eq 2
test "$(grep -c 'codesign --verify --strict' .github/workflows/release.yml)" -eq 2
grep -F 'codesign --verify --strict ./backup-folder' .github/workflows/release.yml
grep -F 'codesign --verify --strict "$watcher_bin"' .github/workflows/release.yml
if grep -F 'spctl' .github/workflows/release.yml; then exit 1; fi
git fetch origin main
parent="$(git rev-parse HEAD^)"
base="$(git merge-base HEAD origin/main)"
test "$parent" = "$base"
git diff --exit-code "$parent" -- .github/workflows scripts launchd AGENTS.md README.md
if git diff --name-only "$parent" -- intent | grep -v '^intent/mac-setup-decisions/plan.md$'; then exit 1; fi
```

### Not in this phase

The spec pull request. It contains only `intent/mac-setup-decisions/` and does not start the steps above.

## Phase 0 build note

Built 2026-10-31 on branch `cursor/mac-setup-phase0-ed7d` from `origin/main` at `994e1fbf4a5d83498ffafecf3a54740921f041fb`. Edited `docs/setup.md`, `docs/restore.md`, `tests/release-workflow.sh`, and `tests/setup-docs.sh` per spec FR2–FR7. No departure from spec; workflows, scripts, and other intent folders unchanged.
