# plan.md — Local pins

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 3 |
| Status | Draft 3 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

The pull request that adds this folder does not start Phase 0. Phase 0 starts only when someone says to build. It is one pull request, opened ready for review, with a conventional commit. After a fresh-context review against the spec and green `macos` and `linux` checks, that pull request is merged. Merging it publishes the next patch tag. That is acceptable (spec AC9). The build does not push a tag by hand, does not add a release label, does not set a real pin, and does not run the installer against a home directory.

## Stops

None. Publishing the next patch tag on merge is accepted in spec D3. It is not a stop.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `git ls-files` and `git check-ignore` commands below | 0 |
| AC2 | `pins.txt.example` data lines | 0 |
| AC3 | `bash tests/install-tools-test.sh` (temporary `HOME`, `PINS_FILE` unset) | 0 |
| AC4 | `bash tests/install-tools-test.sh` | 0 |
| AC5 | `bash tests/setup-docs.sh`, `bash tests/no-secrets.sh`, `bash tests/release-workflow.sh` | 0 |
| AC6 | `git grep` outside `intent/` | 0 |
| AC7 | `git diff` path list; `test.yml` job names and timeouts | 0 |
| AC8 | Spec-and-plan pull request diff is only `intent/local-pins/` | this pull request, not Phase 0 |
| AC9 | No edit to `release.yml` or `scripts/release-version.sh` | 0 |

## Phase 0 — Local pin file and generic installer

Files: `.gitignore`, `pins.txt` (removed), `pins.txt.example` (added), `scripts/install-roger-tools.sh` (renamed to `scripts/install-tools.sh`), `tests/install-roger-tools-test.sh` (renamed to `tests/install-tools-test.sh`), `AGENTS.md`, `docs/setup.md`, `docs/restore.md`, `tests/setup-docs.sh`, `tests/no-secrets.sh`, `tests/release-workflow.sh`, `.github/workflows/test.yml`.

Do not edit: `.github/workflows/release.yml`, `scripts/release-version.sh`, `.github/workflows/codeql.yml`, `README.md`, `.cursor/install.sh`, `launchd/`, or any prior folder under `intent/`.

1. `git rm pins.txt`. Add `/pins.txt` to `.gitignore`. Add `pins.txt.example` with the comments and the two `unpinned` data lines in spec FR2. No real `v*` tag.
2. `git mv scripts/install-roger-tools.sh scripts/install-tools.sh`. `git mv tests/install-roger-tools-test.sh tests/install-tools-test.sh`. Apply spec FR4, FR5, and FR6. Keep `PINS_FILE` and `GH_REPO`. Default pin path `${HOME}/.config/backup-folder/pins.txt`. Function `install_refuse`. Log prefix `install-tools:`. Temp prefix `install-tools.`. Do not create `~/.config/backup-folder`. Do not default to `$ROOT/pins.txt`. Do not read `pins.txt.example`. Do not add `SHA256SUMS` or a source build.
3. Extend `tests/install-tools-test.sh` with the unset-`PINS_FILE` cases in spec AC3. The missing-file case uses a temporary `HOME` where `~/.config/backup-folder` does not exist. The success case uses a different temporary `HOME` and copies `pins.txt.example` itself, comments included, to `$HOME/.config/backup-folder/pins.txt`. Neither case sees `~/bin` created by the stub-`gh` case. Keep every current case. Point the script path, the sourced function, and the prefixes at the new names. Healthy line `install-tools-test: all checks passed`.
4. Update the four `AGENTS.md` mentions (the install-test bullet, the pins bullet, the `~/bin` convention, and the "do not run the installer" bullet) per spec FR7. The first three point at `~/.config/backup-folder/pins.txt` or `pins.txt.example`. Remove every backticked `` `pins.txt` ``. Leave the CodeQL bullet and the release-workflow bullet unchanged.
5. In `docs/setup.md` and `docs/restore.md`, edit the existing installer bullets only. Name `scripts/install-tools.sh` and `~/.config/backup-folder/pins.txt`, and link `pins.txt.example`. Remove the `../pins.txt` link targets. Do not add or remove a `Manual:` or `Script:` bullet. Counts stay 33 and 7.
6. In `tests/setup-docs.sh`, replace both `install-roger-tools.sh` anchors with `install-tools.sh`. Require `.config/backup-folder/pins.txt` and `pins.txt.example` in both docs.
7. In `.github/workflows/test.yml`, change the `macos` step to `bash tests/install-tools-test.sh`. Rename that step to `Install tools script test`. Do not add the step to `linux`. Do not change `timeout-minutes`, job names, or `codeql.yml`.
8. In `tests/no-secrets.sh`, edit the Python path list that the scan actually reads. The bash `scan_paths` array is unused. Fail if `pins.txt.example` is missing. Keep skipping a missing `pins.txt`. Ban `scripts/install-tools.sh` and keep the ban on `scripts/install-roger-tools.sh`, `launchctl`, and `Backups` in that same regex. In `tests/release-workflow.sh`, fail on `install-tools.sh` and on `install-roger-tools.sh`. Do not use a ban string that is a substring of `tests/install-tools-test.sh`.

DoD: every command below exits 0. Run them from the repo root on the Phase 0 commit. Do not run `bash scripts/install-tools.sh` except as the test does, with its temporary `HOME`. `base` is the merge-base with `origin/main`, so a committed edit to a forbidden file still fails.

```
set -euo pipefail
out="$(bash tests/install-tools-test.sh)"
printf '%s\n' "$out" | grep -F 'install-tools-test: all checks passed'
bash tests/setup-docs.sh
bash tests/no-secrets.sh
bash tests/release-workflow.sh
test -z "$(git ls-files pins.txt scripts/install-roger-tools.sh tests/install-roger-tools-test.sh)"
test "$(git ls-files pins.txt.example scripts/install-tools.sh tests/install-tools-test.sh | wc -l | tr -d ' ')" -eq 3
git check-ignore -q pins.txt
if git check-ignore -q pins.txt.example; then exit 1; fi
python3 - <<'PY'
import pathlib, re, sys
raw = pathlib.Path("pins.txt.example").read_text()
if re.search(r"v[0-9]", raw):
    sys.exit("pins.txt.example contains a v* pin")
lines = []
for line in raw.splitlines():
    line = line.split("#", 1)[0].strip()
    if line:
        lines.append(line)
want = ["backup-folder unpinned", "drop-box-watcher unpinned"]
if lines != want:
    sys.exit(f"pins.txt.example data lines: {lines}")
PY
if grep -Rqi roger scripts/install-tools.sh tests/install-tools-test.sh; then exit 1; fi
grep -F 'scripts/install-tools.sh' AGENTS.md
grep -F 'tests/install-tools-test.sh' AGENTS.md
grep -F '~/.config/backup-folder/pins.txt' AGENTS.md
grep -F 'pins.txt.example' AGENTS.md
test -z "$(git grep -l install-roger-tools -- . ':(exclude)intent' ':(exclude)tests/no-secrets.sh' ':(exclude)tests/release-workflow.sh')"
test -z "$(grep -E '\]\(\.\./pins\.txt\)' docs/setup.md docs/restore.md || true)"
if grep -F '`pins.txt`' AGENTS.md docs/setup.md docs/restore.md; then exit 1; fi
base="$(git merge-base HEAD origin/main)"
git diff --exit-code "$base" -- .github/workflows/release.yml scripts/release-version.sh .github/workflows/codeql.yml README.md .cursor/install.sh launchd
if git diff --name-only "$base" -- intent | grep -v '^intent/local-pins/'; then exit 1; fi
if git diff "$base" -- .github/workflows/test.yml | grep -E '^[+-].*timeout-minutes'; then exit 1; fi
test "$(awk '/^  macos:/{j="macos"} /^  linux:/{j="linux"} /install-tools-test.sh/{print j}' .github/workflows/test.yml)" = "macos"
if grep -F 'Install Roger tools' .github/workflows/test.yml; then exit 1; fi
grep -F 'Install tools script test' .github/workflows/test.yml
```

### Not in this phase

The spec-and-plan pull request. It contains only `intent/local-pins/` and does not start the steps above.
