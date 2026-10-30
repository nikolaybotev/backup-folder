#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "no-secrets: $*" >&2
  exit 1
}

ok() {
  echo "no-secrets: $*"
}

BACKUP_PLIST="$ROOT/launchd/backup-folder.plist.template"
WG_PLIST="$ROOT/launchd/com.wireguard.wg0.plist.template"
WG_CONF="$ROOT/launchd/wg0.conf.template"

[[ -f "$BACKUP_PLIST" ]] || fail "missing $BACKUP_PLIST"
[[ -f "$WG_PLIST" ]] || fail "missing $WG_PLIST"
[[ -f "$WG_CONF" ]] || fail "missing $WG_CONF"

python3 <<'PY'
import plistlib
import pathlib
import sys

root = pathlib.Path(".")
backup = root / "launchd/backup-folder.plist.template"
wg = root / "launchd/com.wireguard.wg0.plist.template"

def load_plist(path: pathlib.Path) -> dict:
    with path.open("rb") as f:
        return plistlib.load(f)

b = load_plist(backup)
if b.get("Label") != "com.nikolay.backup.NAME":
    sys.exit(f"backup Label: {b.get('Label')!r}")
args = b.get("ProgramArguments") or []
want_args = ["/Users/USER/bin/backup-folder", "/ABS/SOURCE", "/ABS/BACKUP-DIR"]
if args != want_args:
    sys.exit(f"backup ProgramArguments: {args!r}")
if "StartInterval" in b:
    sys.exit("backup template must not contain StartInterval")
sci = b.get("StartCalendarInterval")
if not isinstance(sci, dict) or sci.get("Minute") != 0:
    sys.exit(f"backup StartCalendarInterval: {sci!r}")
if "Hour" in sci:
    sys.exit("backup StartCalendarInterval must not set Hour")
if b.get("RunAtLoad") is not False:
    sys.exit(f"backup RunAtLoad: {b.get('RunAtLoad')!r}")

w = load_plist(wg)
if w.get("Label") != "com.wireguard.wg0":
    sys.exit(f"wireguard Label: {w.get('Label')!r}")
wargs = w.get("ProgramArguments") or []
if wargs != ["/opt/homebrew/bin/wg-quick", "up", "wg0"]:
    sys.exit(f"wireguard ProgramArguments: {wargs!r}")
env = (w.get("EnvironmentVariables") or {}).get("PATH")
want_path = "/opt/homebrew/sbin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
if env != want_path:
    sys.exit(f"wireguard PATH: {env!r}")
if w.get("RunAtLoad") is not True:
    sys.exit(f"wireguard RunAtLoad: {w.get('RunAtLoad')!r}")
if w.get("KeepAlive") is not True:
    sys.exit(f"wireguard KeepAlive: {w.get('KeepAlive')!r}")
if w.get("StandardErrorPath") != "/var/log/wireguard-wg0.err":
    sys.exit(f"wireguard StandardErrorPath: {w.get('StandardErrorPath')!r}")

conf_path = root / "launchd/wg0.conf.template"
want_lines = [
    "[Interface]",
    "PrivateKey = [PRIVATE_KEY]",
    "Address = [INTERFACE_ADDRESS]",
    "DNS = [DNS]",
    "",
    "[Peer]",
    "PublicKey = [SERVER_PUBLIC_KEY]",
    "PresharedKey = [PRESHARED_KEY]",
    "AllowedIPs = [ALLOWED_IPS]",
    "Endpoint = [SERVER_PUBLIC_IP]:[PORT]",
    "PersistentKeepalive = 25",
]
got = conf_path.read_text(encoding="utf-8").splitlines()
if got != want_lines:
    sys.exit("wg0.conf.template does not match FR4 (body lines differ)")

print("plist and wg0.conf.template structure OK")
PY

[[ -f "$ROOT/pins.txt.example" ]] || fail "missing pins.txt.example"

scan_paths=()
scan_paths+=("$ROOT/intent")
scan_paths+=("$ROOT/launchd")
[[ -d "$ROOT/docs" ]] && scan_paths+=("$ROOT/docs")
[[ -d "$ROOT/scripts" ]] && scan_paths+=("$ROOT/scripts")
[[ -f "$ROOT/README.md" ]] && scan_paths+=("$ROOT/README.md")
[[ -f "$ROOT/pins.txt" ]] && scan_paths+=("$ROOT/pins.txt")
scan_paths+=("$ROOT/.github/workflows")

python3 <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(".")
paths: list[pathlib.Path] = []
for rel in [
    "intent",
    "launchd",
    "docs",
    "scripts",
    "README.md",
    "pins.txt.example",
    "pins.txt",
    ".github/workflows",
]:
    p = root / rel
    if not p.exists():
        continue
    if p.is_file():
        paths.append(p)
    else:
        paths.extend(sorted(p.rglob("*")))

paths = [p for p in paths if p.is_file()]
paths = [p for p in paths if p.name != "no-secrets.sh"]

wg_key = re.compile(r"[A-Za-z0-9+/]{43}=")
op_uri = re.compile(r"op://")
ipv4 = re.compile(
    r"(?<![\[\w/])"
    r"(?:(?:25[0-5]|2[0-4][0-9]|[01]?\d{1,2})\.){3}"
    r"(?:25[0-5]|2[0-4][0-9]|[01]?\d{1,2})"
    r"(?![\]\d])"
)
# Colon followed immediately by decimal digits (port suffix), not bracket placeholders.
port_suffix = re.compile(r"(?<![\[\w]):(\d{1,5})(?![0-9])")
# IPv6: at least two colon-separated hex groups (covers compressed forms in prose).
ipv6 = re.compile(
    r"(?<![\[\w/])"
    r"(?:[0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}"
    r"(?![\]\w])"
)

workflow_banned = re.compile(
    r"scripts/install-tools\.sh|scripts/install-roger-tools\.sh|launchctl|\bBackups\b"
)

violations: list[str] = []

for path in paths:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        violations.append(f"{path}: read error: {e}")
        continue
    rel = path.relative_to(root)
    if op_uri.search(text):
        violations.append(f"{rel}: op:// URI")
    if wg_key.search(text):
        violations.append(f"{rel}: WireGuard-key-shaped token")
    if ipv4.search(text):
        violations.append(f"{rel}: IPv4 literal")
    if ipv6.search(text):
        # Ignore DOCTYPE URLs and other http(s) hostnames without IPv6
        for m in ipv6.finditer(text):
            frag = m.group(0)
            if "apple.com" in text[max(0, m.start() - 20) : m.end() + 20]:
                continue
            if re.fullmatch(r"[0-9a-fA-F:]+", frag) and ":" in frag:
                violations.append(f"{rel}: IPv6 literal ({frag})")
                break
    if port_suffix.search(text):
        violations.append(f"{rel}: numeric port suffix")
    if rel.parts[0:2] == (".github", "workflows") and workflow_banned.search(text):
        violations.append(f"{rel}: banned workflow content (install-roger-tools, launchctl, or Backups)")

if violations:
    for v in violations:
        print(v, file=sys.stderr)
    sys.exit(1)

print("secret scan OK")
PY

ok "all checks passed"
