#!/usr/bin/env python3
"""Read recent Ark Seedance tasks after an ambiguous local submission."""

from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if value[:1] == value[-1:] and value[:1] in {"'", '"'}:
            value = value[1:-1]
        values[key.strip()] = value
    return values


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("attempt", type=Path)
    args = parser.parse_args()
    attempt_path = args.attempt if args.attempt.is_absolute() else ROOT / args.attempt
    attempt = json.loads(attempt_path.read_text(encoding="utf-8"))
    started = int(attempt["requestStartedEpoch"])
    env = load_dotenv(ROOT / ".env.local")
    query = urllib.parse.urlencode({"page_num": 1, "page_size": 100})
    endpoint = env["ARK_BASE_URL"].rstrip("/") + "/contents/generations/tasks?" + query
    request = urllib.request.Request(endpoint, headers={"Authorization": f"Bearer {env['ARK_API_KEY']}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    tasks = payload.get("items") or payload.get("data") or []
    recent = []
    for task in tasks:
        created = int(task.get("created_at") or 0)
        if created >= started - 60:
            recent.append({
                "id": task.get("id"),
                "model": task.get("model"),
                "status": task.get("status"),
                "created_at": created,
            })
    print(json.dumps({"requestStartedEpoch": started, "recentTasks": recent}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
