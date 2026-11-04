import os
import subprocess
import sys


def run(base_path):
    """Fail the build when a MingCute icon's ink is under 0.9 of the upstream icon."""
    script = os.path.join(base_path, "Tellomi", "Icons", "check_sizes.py")
    if not os.path.isfile(script):
        sys.stderr.write("IconSizeCheck: missing {}\n".format(script))
        return 1
    completed = subprocess.run([sys.executable, script], cwd=base_path)
    return completed.returncode
