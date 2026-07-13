#!/usr/bin/env bash
# heavy validation をマシン全体で 1 本に直列化する lease で包んでコマンドを実行する。
# OS の advisory lock (flock) を使うため、取得・解放・クラッシュ時解放を kernel が保証する。
# stale 判定・強制解放・owner 管理は不要。
#
# 使い方: validation-lease.sh <command> [args...]
# lock ファイルは VALIDATION_LEASE_FILE で上書きできる。
# lock 待ち時間は stderr の "[lease]" 行に出る。worker はこれを external wait として検証台帳に記録する。
set -u

if [ "$#" -eq 0 ]; then
  echo "usage: validation-lease.sh <command> [args...]" >&2
  exit 2
fi

LEASE_FILE="${VALIDATION_LEASE_FILE:-/tmp/issue-pr-autopilot/validation.lease}"
mkdir -p "$(dirname "$LEASE_FILE")"

exec python3 - "$LEASE_FILE" "$@" <<'PY'
import fcntl
import subprocess
import sys
import time

lease_path, cmd = sys.argv[1], sys.argv[2:]
lease = open(lease_path, "a")
start = time.monotonic()
try:
    fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
    print("[lease] acquired immediately", file=sys.stderr)
except OSError:
    print(f"[lease] waiting for validation lease: {lease_path}", file=sys.stderr)
    fcntl.flock(lease, fcntl.LOCK_EX)
    print(f"[lease] acquired after {time.monotonic() - start:.0f}s wait", file=sys.stderr)

sys.exit(subprocess.run(cmd).returncode)
PY
