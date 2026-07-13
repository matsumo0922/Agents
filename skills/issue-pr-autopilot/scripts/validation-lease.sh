#!/usr/bin/env bash
# heavy validation をマシン全体で 1 本に直列化する lease で包んでコマンドを実行する。
# OS の advisory lock (flock) を使うため、lock の取得・解放・クラッシュ時解放を kernel が保証する。
# stale 判定・強制解放・owner 管理は不要。
#
# 検証コマンドは専用 process group で起動し、SIGINT / SIGTERM / SIGHUP を group へ転送して
# 子の終了を待ってから lock を解放する（wrapper だけが停止して検証プロセスと新しい lock 保持者が
# 並走することを防ぐ）。SIGKILL だけは転送できないため、その経路では実行環境が process group
# 全体を停止することを前提とする。
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
import os
import signal
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

proc = subprocess.Popen(cmd, start_new_session=True)


def forward(signum, _frame):
    try:
        os.killpg(proc.pid, signum)
    except ProcessLookupError:
        pass


for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, forward)

while True:
    try:
        sys.exit(proc.wait())
    except KeyboardInterrupt:
        continue
PY
