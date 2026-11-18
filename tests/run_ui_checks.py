"""Compile AppKit regression checks without launching the backend or editing preferences."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "MyBackupApp.swift").read_text()
source = source.rsplit("let app = NSApplication.shared", 1)[0]
with tempfile.TemporaryDirectory(prefix="mybackup-ui-") as temporary:
    folder = Path(temporary)
    combined = folder / "main.swift"
    combined.write_text(source + (root / "tests/ui_regression.swift").read_text())
    executable = folder / "ui-checks"
    subprocess.run(["swiftc", "-module-cache-path", str(folder / "ModuleCache"), str(combined),
                    "-o", str(executable), "-framework", "Cocoa"], check=True)
    subprocess.run([str(executable)], check=True)
