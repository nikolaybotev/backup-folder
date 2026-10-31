# plan.md — Generic docs

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 3 |
| Status | Draft 4 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it. The only allowed edit under `intent/` during Phase 0 is an appended build note on this file. Do not edit any other `intent/` folder, and do not rewrite the spec.

The pull request that adds this folder does not start Phase 0. Phase 0 starts only when someone says to build, and only after this pull request is on `main`. It is one commit on a new branch from that `main`, one pull request, opened ready for review, with a conventional commit. A fresh-context review reads it against the spec. Required checks stay `macos` and `linux`. Phase 0 does not merge that pull request. Merging the spec-and-plan pull request publishes the next patch tag. That is acceptable (spec AC6). The spec-and-plan author does not merge it in the session that only writes this folder. Neither pull request adds a release label or pushes a tag by hand.

## Stops

**Grooming merge.** After the Phase 0 pull request is open, reviewed, and green, stop. Do not merge it. The body holds the remaining-the deployment Mac report from spec FR9. The maintainer reviews that report in chat. A later change merges, or edits the docs again, only after he answers. Publishing a patch tag from the spec-and-plan merge is not a stop (spec D11).

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | Spec-and-plan diff is only `intent/generic-docs/` | this pull request, not Phase 0 |
| AC2 | `git grep for machine names` over the long-lived set; README and setup sentences; the five `AGENTS.md` the maintainer phrases in spec FR5 | 0 |
| AC3 | `bash tests/setup-docs.sh` | 0 |
| AC4 | `bash tests/no-secrets.sh`, `bash tests/release-workflow.sh`, `git diff` path list | 0 |
| AC5 | Grooming pull request body, left unmerged | 0 |
| AC6 | This pull request does not edit `release.yml` or `scripts/release-version.sh` (AC1). Job `publish` on push to `main`, and the unlabeled patch path, stay as spec section 9 read them | this pull request, not Phase 0 |

## Phase 0 — Generic long-lived docs

Files: `README.md`, `docs/setup.md`, `docs/restore.md`, `AGENTS.md`, `REVIEW.md`, `tests/setup-docs.sh`.

Do not edit: `launchd/`, `scripts/`, `pins.txt.example`, `drop-box-watcher.example.toml`, `.github/workflows/release.yml`, `scripts/release-version.sh`, `.github/workflows/codeql.yml`, `.github/workflows/test.yml`, `.cursor/install.sh`, or any `intent/` folder other than an appended build note on this plan.

1. Apply spec FR2, FR3, and FR4 to `docs/setup.md`, `docs/restore.md`, and `README.md`. Keep the 33 and 7 bullets. Remove every case-insensitive machine name. Keep volume `External`, the eight-hundred-gigabyte quota, `com.nikolay.backup.NAME`, `com.nikolay.drop-box-watcher`, `the signing identity`, and the public `OWNER/bootstrap` and `OWNER/code-signing` URLs. Keep `(Q2)`, `(Q3)`, and `(Q6)`. Point the setup watcher bullet at `launchd/drop-box-watcher.plist.template`. In the restore bullet that repeats LaunchAgent installs, delete "once its template exists" and name that same template. Replace the false "does not publish a binary" sentence as FR4 requires. Leave the README sentences that already say to replace `/ABS/PATH/TO/HOME`. Leave `launchctl bootstrap gui/$(id -u)` as the numeric uid.
2. Apply spec FR5 to `AGENTS.md` and spec FR6 to `REVIEW.md`. Remove operator-specific install phrasing listed in FR5. Keep `the signing identity`. Replace only the compliance sentence that names the deployment Mac bootstrap phases. Leave the rest of that bullet, including the absent protect-main sentence. Stop treating job `publish` in `.github/workflows/release.yml` as an Important defect. Keep Important for any other workflow that publishes on a push to `main`. Do not rename the signing identity.
3. In `tests/setup-docs.sh`, replace the setup anchor `the Bonjour name` with `Choose a computer name`. Do not use `.local`. That string is contained in `the Bonjour name`. Replace the setup anchor `a named Time Machine volume` with `Time Machine volume`. Add `drop-box-watcher.plist.template` to the setup anchors. Do not add `file-access policy` to the setup anchors. Replace the restore anchor `a named Time Machine volume` with `Time Machine volume` and the restore anchor `file-access-policy` with `file-access policy`. Leave the other anchors and the counts 33 and 7.
4. Do not rename `scripts/install-tools.sh`. Do not edit a plist. Do not add a template comment. Do not run `scripts/install-tools.sh` or `scripts/ensure-backup-dirs.sh` against a home directory. Do not write `~/Backups`. Do not put a WireGuard key, public IP, or port in the diff.
5. Open one pull request, ready for review, conventional commit. The body includes the FR9 report: run the grep in the DoD, and either say that no host-name mentions remain in the long-lived docs, or list each hit with a link to that line on the pull request branch, the exact sentence, and why it was kept. Also one sentence that the scan does not cover operator role names, `OWNER`, or `com.nikolay`, and that what stays is the signing identity and `com.nikolay.*` labels (spec D7) plus the repo name and the public bootstrap and code-signing URLs (spec D9). Do not merge.

DoD: every command below exits 0. Run them from the repo root on the Phase 0 commit. That commit's parent is `main` after this folder is already on `main`. `git fetch` makes `origin/main` that commit. A branch that still contains the unmerged spec commits fails the parent check on purpose.

```
set -euo pipefail
bash tests/setup-docs.sh
bash tests/no-secrets.sh
bash tests/release-workflow.sh
if git grep for machine names -- README.md docs AGENTS.md REVIEW.md launchd scripts pins.txt.example drop-box-watcher.example.toml; then
  exit 1
fi
if grep -F 'does not publish a binary' README.md; then exit 1; fi
if grep -F 'not in this repo yet' docs/setup.md; then exit 1; fi
if grep -F 'once its template exists' docs/restore.md; then exit 1; fi
if grep -F 'file-access policy' docs/setup.md; then exit 1; fi
grep -F 'drop-box-watcher.plist.template' docs/setup.md
grep -F 'Choose a computer name' docs/setup.md
grep -F 'file-access policy' docs/restore.md
grep -F 'can push the next patch tag' README.md
grep -F 'the signing identity' AGENTS.md
if grep -F 'the maintainer passes absolute' AGENTS.md; then exit 1; fi
if grep -F 'the maintainer fills them' AGENTS.md; then exit 1; fi
if grep -F 'the maintainer sets a real pin' AGENTS.md; then exit 1; fi
if grep -F 'the maintainer follows' AGENTS.md; then exit 1; fi
if grep -F 'the maintainer runs' AGENTS.md; then exit 1; fi
git fetch origin main
parent="$(git rev-parse HEAD^)"
base="$(git merge-base HEAD origin/main)"
test "$parent" = "$base"
git diff --exit-code "$parent" -- launchd scripts .github/workflows/release.yml scripts/release-version.sh .github/workflows/codeql.yml .github/workflows/test.yml .cursor/install.sh pins.txt.example drop-box-watcher.example.toml
if git diff --name-only "$parent" -- intent | grep -v '^intent/generic-docs/plan.md$'; then exit 1; fi
```

### Not in this phase

The spec-and-plan pull request. It contains only `intent/generic-docs/` and does not start the steps above.

**Later, not this change.** `scripts/install-tools.sh` stays. If `.cursor/install.sh` ever stops being the Cloud Agent environment installer, a later decision can rename `scripts/install-tools.sh` to `scripts/install.sh`. Until that collision is gone, do not rename it. Checked on `0b5e84d`: `.cursor/environment.json` sets `"install": "bash .cursor/install.sh"`, and that script is the mise and Swift installer.

Label prefix, closed by [signing-identity](../signing-identity/plan.md): `backup.NAME` and `drop-box-watcher` use the prefix `com.nikolaybotev.`. The signing identity is `SIGN_IDENTITY` when set, otherwise the certificate imported from `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD`.
