#!/usr/bin/env bash
# heavy validation をマシン全体で 1 本に直列化する lease で包んでコマンドを実行する。
# OS の advisory lock (flock) を使うため、lock の取得・解放・クラッシュ時解放を kernel が保証する。
# stale 判定・強制解放・owner 管理は不要。
#
# lock fd は検証プロセスにも継承させる。flock は open file description に紐づくため、
# wrapper が先に死んでも（SIGKILL を含む）検証プロセスが生きている限り lock は保持され、
# 「新しい lease 保持者 + 生存中の旧検証プロセス」の並走は起きない。
# 検証コマンドは専用 process group で起動し、SIGINT / SIGTERM / SIGHUP を group へ転送して
# 子の終了を待ってから lock を解放する。
#
# 使い方: validation-lease.sh <command> [args...]
# lock ファイルは VALIDATION_LEASE_FILE で上書きできる。
# lock 待ち時間は stderr の "[lease]" 行に出る。worker はこれを external wait として検証台帳に記録する。
set -u

if [ "$#" -eq 0 ]; then
  echo "usage: validation-lease.sh <command> [args...]" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "validation-lease: python3 not found (required for flock wrapper)" >&2
  exit 3
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

proc = None
pending = []


def forward(signum, _frame):
    if proc is None:
        pending.append(signum)
        return
    try:
        os.killpg(proc.pid, signum)
    except ProcessLookupError:
        pass


# handler は Popen より先に登録する（登録前に信号を受けて wrapper だけが
# 死に、別 process group の子が残る窓を無くす）。
for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, forward)

proc = subprocess.Popen(cmd, start_new_session=True, pass_fds=(lease.fileno(),))
for signum in pending:
    forward(signum, None)

sys.exit(proc.wait())
PY
