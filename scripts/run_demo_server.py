#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from demo.server import main  # noqa: E402


if __name__ == "__main__":
    print("Starting CrispyBrain demo server in local fallback mode.")
    print("Preferred runtime: docker compose service `crispybrain-demo-ui` in the AI Lab.")
    main()
