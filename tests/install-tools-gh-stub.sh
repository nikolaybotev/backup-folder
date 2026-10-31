# Faithful gh stub for install-tools tests: release download refuses existing --output
# without --clobber; attestation verify succeeds. Honors GH_ARGS_LOG when set.
install_tools_write_gh_stub() {
  local stub_dir="$1"
  mkdir -p "$stub_dir"
  cat >"$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_ARGS_LOG:-}" ]]; then
  printf '%s\n' "$*" >> "$GH_ARGS_LOG"
fi
if [[ "${1:-}" == "attestation" && "${2:-}" == "verify" ]]; then
  exit 0
fi
if [[ "${1:-}" == "release" && "${2:-}" == "download" ]]; then
  clobber=0
  outfile=""
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --clobber)
        clobber=1
        shift
        ;;
      --output)
        outfile="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  if [[ -n "$outfile" ]]; then
    if [[ -e "$outfile" && "$clobber" -eq 0 ]]; then
      echo "already exists (use \`--clobber\` to overwrite file or \`--skip-existing\` to skip file)" >&2
      exit 1
    fi
    printf 'stub-binary' >"$outfile"
  fi
  exit 0
fi
exit 0
STUB
  chmod +x "$stub_dir/gh"
}
