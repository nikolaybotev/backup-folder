#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "test-webhook: $*" >&2
  exit 1
}

ok() {
  echo "test-webhook: $*"
}

HELPER="$ROOT/scripts/test-webhook.sh"
[[ -x "$HELPER" ]] || fail "missing or non-executable $HELPER"

DUMMY_KEY="test-webhook-integration-key"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-webhook.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

MISSING="$TMPROOT/missing.toml"
set +e
"$HELPER" "$MISSING" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  fail "expected nonzero exit for missing config file"
fi

PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

POSTS="$TMPROOT/posts.ndjson"
HTTP_PY="$TMPROOT/http_server.py"

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

python3 -u "$HTTP_PY" "$PORT" "$POSTS" &
HTTP_PID=$!
trap 'kill "$HTTP_PID" 2>/dev/null || true; rm -rf "$TMPROOT"' EXIT

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if python3 -c "import socket; s=socket.create_connection(('127.0.0.1', ${PORT}), 0.2); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

CFG="$TMPROOT/config.toml"
cat >"$CFG" <<EOF
watch_folder = "/tmp/test-webhook-watch"
[webhook]
url = "http://127.0.0.1:${PORT}/"
key = "${DUMMY_KEY}"
[log]
path = "${TMPROOT}/log"
EOF

OUT="$TMPROOT/helper.out"
set +e
"$HELPER" "$CFG" >"$OUT" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  cat "$OUT" >&2
  fail "helper exited $rc"
fi

if grep -q "$DUMMY_KEY" "$OUT"; then
  fail "helper stdout/stderr must not contain the dummy key"
fi

if ! grep -q 'HTTP 200' "$OUT"; then
  cat "$OUT" >&2
  fail "expected HTTP 200 in helper output"
fi

sleep 0.2

if [[ ! -s "$POSTS" ]]; then
  fail "loopback server received no POST"
fi

python3 - "$POSTS" "$DUMMY_KEY" <<'PY'
import json, sys

posts_path = sys.argv[1]
key = sys.argv[2]
lines = open(posts_path).read().splitlines()
if not lines:
    sys.exit("no POST recorded")
rec = json.loads(lines[-1])
want_auth = f"Bearer {key}"
if rec.get("authorization") != want_auth:
    sys.exit(f"authorization: {rec.get('authorization')!r} want {want_auth!r}")
body = json.loads(rec["body"])
if body != {"source": "manual", "files": []}:
    sys.exit(f"body: {body!r}")
PY

ok "OK"
