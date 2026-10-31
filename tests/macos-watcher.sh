#!/usr/bin/env bash
# AC6 — macOS watcher smoke (harness may poll; product readiness path does not sleep).
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macos-watcher: requires macOS" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/drop-box-watcher" && -x "$ROOT/drop-box-watcher" ]]; then
  BIN="$ROOT/drop-box-watcher"
elif [[ -x "$ROOT/drop-box-watcher/drop-box-watcher" ]]; then
  BIN="$ROOT/drop-box-watcher/drop-box-watcher"
else
  echo "Missing drop-box-watcher binary; run bash scripts/build.sh" >&2
  exit 1
fi

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/macos-watcher-XXXXXX")"
REAL_WATCH="$TMPROOT/watch-real"
LINK_WATCH="/tmp/macos-watcher-watch-$$"
LOG="$TMPROOT/watcher.log"
POSTS="$TMPROOT/posts.jsonl"
WATCHER_STDERR="$TMPROOT/watcher.stderr"
WATCHER_STDOUT="$TMPROOT/watcher.stdout"
CONFIG="$TMPROOT/config.toml"
LOOSE="$TMPROOT/loose.toml"
HTTP_PY="$TMPROOT/http_server.py"
CONFIG_LOG_PY="$TMPROOT/config_log_path.py"
LOG_CONTAINS_PY="$TMPROOT/log_file_contains.py"
PRINT_LOG_HEAD_PY="$TMPROOT/print_log_head.py"
POLL_FOR_FILES_PY="$TMPROOT/poll_for_files.py"
HTTP_PID=""
WATCHER_PID=""

cleanup() {
  if [[ -n "${HTTP_PID:-}" ]]; then kill "$HTTP_PID" 2>/dev/null || true; fi
  if [[ -n "${WATCHER_PID:-}" ]]; then kill "$WATCHER_PID" 2>/dev/null || true; fi
  rm -f "$LINK_WATCH"
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

echo "macos-watcher: build OK"

set +e
"$BIN" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "macos-watcher: expected exit 2 with no arguments, got $rc" >&2
  exit 1
fi

mkdir -p "$REAL_WATCH"
ln -sf "$REAL_WATCH" "$LINK_WATCH"

cat >"$LOOSE.toml" <<EOF
watch_folder = "$LINK_WATCH"
[webhook]
url = "http://127.0.0.1:9/"
key = "k"
[behavior]
ignore = [".DS_Store"]
[log]
path = "$LOG"
EOF
chmod 0644 "$LOOSE.toml"
set +e
"$BIN" "$LOOSE.toml" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "macos-watcher: expected exit 2 for loose config permissions, got $rc" >&2
  exit 1
fi

PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

TEST_KEY="macos-watcher-test-key"

cat >"$HTTP_PY" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])
out_path = sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        auth = self.headers.get("Authorization", "")
        record = {"authorization": auth, "body": body.decode("utf-8", errors="replace")}
        with open(out_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")
        self.send_response(200)
        self.end_headers()

HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY

cat >"$CONFIG_LOG_PY" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'^\s*path\s*=\s*"((?:\\.|[^"\\])*)"', text, re.M)
if not m:
    sys.exit(1)
s = m.group(1).replace("\\\\", "\\").replace('\\"', '"')
print(s, end="")
PY

cat >"$LOG_CONTAINS_PY" <<'PY'
import os, sys
path, needle = sys.argv[1], sys.argv[2]
if not os.path.isfile(path) or os.path.getsize(path) == 0:
    sys.exit(1)
with open(path, encoding="utf-8", errors="replace") as f:
    if needle not in f.read():
        sys.exit(1)
PY

cat >"$PRINT_LOG_HEAD_PY" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8", errors="replace") as f:
    for i, line in enumerate(f):
        if i >= 5:
            break
        print(line.rstrip("\n"))
PY

cat >"$POLL_FOR_FILES_PY" <<'PY'
import json, sys
path, want_s, key, skip_s = sys.argv[1:5]
want = json.loads(want_s)
skip = int(skip_s)
try:
    lines = open(path).read().splitlines()
except FileNotFoundError:
    sys.exit(1)
for line in lines[skip:]:
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("authorization") != f"Bearer {key}":
        continue
    body = json.loads(rec["body"])
    if body.get("files") == want:
        sys.exit(0)
sys.exit(1)
PY

python3 -u "$HTTP_PY" "$PORT" "$POSTS" &
HTTP_PID=$!

cat >"$CONFIG" <<EOF
watch_folder = "$LINK_WATCH"
[webhook]
url = "http://127.0.0.1:${PORT}/"
key = "${TEST_KEY}"
[behavior]
ignore = [".DS_Store", ".*", "*.icloud", "*.download", "*.crdownload", "*.part"]
[log]
path = "$LOG"
EOF
chmod 0600 "$CONFIG"

config_log_path() {
  python3 "$CONFIG_LOG_PY" "$CONFIG"
}

log_file_contains() {
  local log_path="$1"
  local needle="$2"
  python3 "$LOG_CONTAINS_PY" "$log_path" "$needle"
}

print_log_head() {
  local log_path="$1"
  python3 "$PRINT_LOG_HEAD_PY" "$log_path"
}

wait_for_log_line() {
  local needle="$1"
  local log_path="$2"
  local timeout_secs="${3:-5}"
  local start end now
  start=$(date +%s)
  end=$((start + timeout_secs))
  while :; do
    now=$(date +%s)
    if (( now >= end )); then
      return 1
    fi
    if log_file_contains "$log_path" "$needle"; then
      echo "macos-watcher: log path=${log_path}" >&2
      echo "macos-watcher: log head after '${needle}':" >&2
      print_log_head "$log_path" >&2
      return 0
    fi
    if ! kill -0 "$WATCHER_PID" 2>/dev/null; then
      return 1
    fi
    sleep 0.1
  done
}

print_watcher_diagnostics() {
  local rc=unknown
  local config_log=""
  if ! kill -0 "$WATCHER_PID" 2>/dev/null; then
    set +e
    wait "$WATCHER_PID" 2>/dev/null
    rc=$?
    set -e
  fi
  config_log="$(config_log_path 2>/dev/null || true)"
  echo "macos-watcher: watcher exit code: ${rc}" >&2
  echo "macos-watcher: harness log path=${LOG}" >&2
  echo "macos-watcher: config [log].path=${config_log}" >&2
  if [[ -f "$LOG" ]]; then
    echo "macos-watcher: log byte size=$(wc -c < "$LOG" | tr -d ' ')" >&2
  fi
  echo "macos-watcher: stdout:" >&2
  cat "$WATCHER_STDOUT" 2>/dev/null >&2 || true
  echo "macos-watcher: stderr:" >&2
  cat "$WATCHER_STDERR" 2>/dev/null >&2 || true
  echo "macos-watcher: log:" >&2
  cat "$LOG" 2>/dev/null >&2 || true
}

CONFIG_LOG="$(config_log_path)"
if [[ -z "$CONFIG_LOG" ]]; then
  echo "macos-watcher: config missing [log].path" >&2
  exit 1
fi
if [[ "$CONFIG_LOG" != "$LOG" ]]; then
  echo "macos-watcher: log path mismatch harness=${LOG} config=${CONFIG_LOG}" >&2
  exit 1
fi
echo "macos-watcher: operational log path=${LOG}" >&2

"$BIN" "$CONFIG" >"$WATCHER_STDOUT" 2>"$WATCHER_STDERR" &
WATCHER_PID=$!

poll_for_files() {
  local want_json="$1"
  local skip_lines="${2:-0}"
  local deadline=$((SECONDS + 10))
  while (( SECONDS < deadline )); do
    if python3 "$POLL_FOR_FILES_PY" "$POSTS" "$want_json" "$TEST_KEY" "$skip_lines"; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

for _ in $(seq 1 50); do
  if kill -0 "$WATCHER_PID" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if ! kill -0 "$WATCHER_PID" 2>/dev/null; then
  echo "macos-watcher: watcher process exited before smoke" >&2
  print_watcher_diagnostics
  exit 1
fi

if ! wait_for_log_line "operational_log path=${LOG}" "$LOG"; then
  echo "macos-watcher: process never wrote operational_log path line" >&2
  print_watcher_diagnostics
  exit 1
fi

if ! wait_for_log_line "started watch_folder=" "$LOG"; then
  echo "macos-watcher: watcher never logged startup (check log path or start())" >&2
  print_watcher_diagnostics
  if ! kill -0 "$WATCHER_PID" 2>/dev/null; then
    echo "macos-watcher: watcher exited during startup wait" >&2
  fi
  exit 1
fi

if ! wait_for_log_line "registered file presenter" "$LOG"; then
  echo "macos-watcher: watcher never registered file presenter on main run loop" >&2
  print_watcher_diagnostics
  exit 1
fi

NOTE_CONTENT="hello-note"
printf '%s' "$NOTE_CONTENT" >"$LINK_WATCH/note.txt"

if ! poll_for_files '["note.txt"]'; then
  echo "macos-watcher: timed out waiting for first nudge for note.txt" >&2
  echo "macos-watcher: posts captured:" >&2
  cat "$POSTS" 2>/dev/null >&2 || true
  print_watcher_diagnostics
  exit 1
fi

actual="$(cat "$LINK_WATCH/note.txt")"
if [[ "$actual" != "$NOTE_CONTENT" ]]; then
  echo "macos-watcher: note.txt bytes changed" >&2
  exit 1
fi
echo "macos-watcher: unchanged OK"

posts_before_ds="$(wc -l < "$POSTS" | tr -d ' ')"
printf 'ds' >"$LINK_WATCH/.DS_Store"
sleep 1
if python3 - "$POSTS" "$posts_before_ds" <<'PY'
import json, sys
path = sys.argv[1]
before = int(sys.argv[2])
lines = open(path).read().splitlines()
for line in lines[before:]:
    rec = json.loads(line)
    body = json.loads(rec["body"])
    if ".DS_Store" in body.get("files", []):
        print("macos-watcher: .DS_Store must not appear in webhook files", file=sys.stderr)
        sys.exit(1)
sys.exit(0)
PY
then
  :
else
  exit 1
fi

printf ' more' >>"$LINK_WATCH/note.txt"
posts_before_grow="$(wc -l < "$POSTS" | tr -d ' ')"
if ! poll_for_files '["note.txt"]' "$posts_before_grow"; then
  echo "macos-watcher: timed out waiting for second nudge after grow" >&2
  cat "$POSTS" 2>/dev/null >&2 || true
  exit 1
fi

post_count="$(wc -l < "$POSTS" | tr -d ' ')"
if [[ "$post_count" -lt 2 ]]; then
  echo "macos-watcher: expected at least two POSTs, got $post_count" >&2
  exit 1
fi

echo "macos-watcher: notify OK"

log_byte_count() {
  wc -c < "$1" | tr -d ' '
}

assert_watcher_alive() {
  if ! kill -0 "$WATCHER_PID" 2>/dev/null; then
    echo "macos-watcher: watcher exited during config reload" >&2
    print_watcher_diagnostics
    exit 1
  fi
}

wait_for_new_log_line() {
  local needle="$1"
  local log_path="$2"
  local start_size="$3"
  local timeout_secs="${4:-10}"
  local deadline=$((SECONDS + timeout_secs))
  while (( SECONDS < deadline )); do
    if ! kill -0 "$WATCHER_PID" 2>/dev/null; then
      return 1
    fi
    if python3 - "$log_path" "$needle" "$start_size" <<'PY'
import sys
path, needle, start = sys.argv[1:]
data = open(path, "rb").read()
sys.exit(0 if needle.encode() in data[int(start):] else 1)
PY
    then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

write_watcher_config() {
  local watch_folder="$1"
  local mode="$2"
  cat >"$CONFIG" <<EOF
watch_folder = "${watch_folder}"
[webhook]
url = "http://127.0.0.1:${PORT}/"
key = "${TEST_KEY}"
[behavior]
ignore = [".DS_Store", ".*", "*.icloud", "*.download", "*.crdownload", "*.part"]
[log]
path = "${LOG}"
EOF
  chmod "$mode" "$CONFIG"
}

reload_size="$(log_byte_count "$LOG")"
cat >"$CONFIG" <<'EOF'
not valid watcher config
EOF
chmod 0600 "$CONFIG"
if ! wait_for_new_log_line "config reload rejected" "$LOG" "$reload_size" 10; then
  echo "macos-watcher: invalid config did not log config reload rejected" >&2
  print_watcher_diagnostics
  exit 1
fi
assert_watcher_alive
posts_before_reload="$(wc -l < "$POSTS" | tr -d ' ')"
printf 'still-watching' >"$LINK_WATCH/reload-note.txt"
if ! poll_for_files '["reload-note.txt"]' "$posts_before_reload"; then
  echo "macos-watcher: old folder did not notify after invalid config" >&2
  cat "$POSTS" 2>/dev/null >&2 || true
  print_watcher_diagnostics
  exit 1
fi

reload_size="$(log_byte_count "$LOG")"
chmod 0644 "$CONFIG"
if ! wait_for_new_log_line "config reload rejected" "$LOG" "$reload_size" 10; then
  echo "macos-watcher: mode 0644 did not log config reload rejected" >&2
  print_watcher_diagnostics
  exit 1
fi
assert_watcher_alive
posts_before_mode="$(wc -l < "$POSTS" | tr -d ' ')"
printf 'still-watching' >"$LINK_WATCH/reload-mode.txt"
if ! poll_for_files '["reload-mode.txt"]' "$posts_before_mode"; then
  echo "macos-watcher: old folder did not notify after mode 0644" >&2
  cat "$POSTS" 2>/dev/null >&2 || true
  print_watcher_diagnostics
  exit 1
fi

WATCH_TWO="$TMPROOT/watch-two"
mkdir -p "$WATCH_TWO"
reload_size="$(log_byte_count "$LOG")"
write_watcher_config "$WATCH_TWO" 600
if ! wait_for_new_log_line "config reloaded" "$LOG" "$reload_size" 10; then
  echo "macos-watcher: valid second folder did not log config reloaded" >&2
  print_watcher_diagnostics
  exit 1
fi
if ! wait_for_new_log_line "fsevents stream started" "$LOG" "$reload_size" 10; then
  echo "macos-watcher: reload did not start the second folder" >&2
  print_watcher_diagnostics
  exit 1
fi
assert_watcher_alive
posts_before_two="$(wc -l < "$POSTS" | tr -d ' ')"
printf 'second-folder' >"$WATCH_TWO/second.txt"
if ! poll_for_files '["second.txt"]' "$posts_before_two"; then
  echo "macos-watcher: second folder did not notify" >&2
  cat "$POSTS" 2>/dev/null >&2 || true
  print_watcher_diagnostics
  exit 1
fi
assert_watcher_alive
