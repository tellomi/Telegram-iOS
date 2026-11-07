import os
import subprocess
import sys


def run(base_path):
    """Fail the build when a chat-list swipe icon does not resolve in the asset catalog."""
    script = os.path.join(base_path, "Tellomi", "Icons", "test_chat_list_swipe.py")
    if not os.path.isfile(script):
        sys.stderr.write("ChatListSwipeCheck: missing {}\n".format(script))
        return 1
    completed = subprocess.run([sys.executable, script], cwd=base_path)
    return completed.returncode
