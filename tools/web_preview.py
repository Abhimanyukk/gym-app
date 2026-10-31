"""Run the debug web preview and refresh it when Dart or assets change."""

import os
from pathlib import Path
import signal
import subprocess
import time


def source_snapshot(tablet: Path) -> dict:
    snapshot = {}
    paths = [*(tablet / "lib").rglob("*.dart"), *(tablet / "assets").rglob("*")]
    for path in paths:
        try:
            if path.is_file():
                stat = path.stat()
                snapshot[path] = (stat.st_mtime_ns, stat.st_size)
        except FileNotFoundError:
            pass  # An editor may replace or delete a file during this scan.
    return snapshot


def main() -> int:
    tablet = Path(__file__).resolve().parents[1] / "tablet"
    subprocess.run(["flutter", "pub", "get"], cwd=tablet, check=True)
    pid_file = tablet / "build" / "web-preview.pid"
    pid_file.parent.mkdir(parents=True, exist_ok=True)
    pid_file.unlink(missing_ok=True)
    process = subprocess.Popen(
        [
            "flutter", "run", "-d", "web-server", "-t", "lib/preview.dart",
            "--web-hostname=0.0.0.0", "--web-port=8080",
            "--no-web-resources-cdn", "--no-pub", f"--pid-file={pid_file}",
        ],
        cwd=tablet,
    )
    signal.signal(signal.SIGTERM, lambda *_: process.terminate())
    previous = source_snapshot(tablet)
    pending = False
    print("UI preview: http://localhost:8080 — watching Dart and assets.")
    try:
        # dover-gain-efficient: poll the Windows bind mount; no watcher dependency.
        while process.poll() is None:
            time.sleep(0.5)
            current = source_snapshot(tablet)
            if current != previous:
                previous = current
                pending = True
            elif pending and pid_file.is_file():
                # dover-gain-efficient: hot restart applies main/initState edits too,
                # at the cost of resetting preview navigation and form state.
                try:
                    os.kill(int(pid_file.read_text()), signal.SIGUSR2)
                except FileNotFoundError:
                    continue  # Flutter is still registering its reload handler.
                except ProcessLookupError:
                    return process.wait()
                print("Source changed — refreshing browser preview.")
                pending = False
        return process.wait()
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
