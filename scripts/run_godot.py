#!/usr/bin/env python3
"""Godot 호출의 제한 시간, 격리 저장, 오류 로그 판정을 한곳에서 적용한다."""
import argparse
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True)
    parser.add_argument("--timeout", type=float, default=float(os.environ.get("GODOT_COMMAND_TIMEOUT_SECONDS", "300")))
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.timeout <= 0:
        parser.error("실행 명령과 양수 제한 시간이 필요하다")
    path = Path(args.log)
    path.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    # 테스트 본문 주입보다 이른 autoload도 실제 저장을 읽지 않는다.
    with tempfile.TemporaryDirectory(prefix="starlit-test-") as save_dir:
        env["STARLIT_SAVE_DIR"] = save_dir
        with path.open("wb") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                       env=env, start_new_session=True)
            try:
                status = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                status = 124
    raw = path.read_text(encoding="utf-8", errors="replace")
    clean = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", raw)
    path.with_suffix(path.suffix + ".clean").write_text(clean, encoding="utf-8")
    errors = re.findall(r"^(?:SCRIPT ERROR|ERROR):.*$", clean, re.MULTILINE)
    if status or errors:
        print(f"[godot] 실패 exit={status}, log={path}", file=sys.stderr)
        print("\n".join(errors[:20] or clean.splitlines()[-30:]), file=sys.stderr)
        return status if status > 0 else 1
    print("\n".join(clean.splitlines()[-3:]))
    print(f"[godot] 통과, log={path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
