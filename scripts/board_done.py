#!/usr/bin/env python3
"""批量把 issue/PR 看板项置为 Done。用法: python3 board_done.py 9 10 11 12 [31 ...]"""
import subprocess
import sys

for n in sys.argv[1:]:
    r = subprocess.run(
        ["python3", "scripts/set_board_status.py", n, "Done"],
        capture_output=True,
        text=True,
    )
    print(n, "ok" if r.returncode == 0 else f"FAIL: {r.stderr.strip()[-200:]}")
