#!/usr/bin/env python3
"""Submit one recorded Seedream image job without automatic retries."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if value[:1] == value[-1:] and value[:1] in {"'", '"'}:
            value = value[1:-1]
        values[key] = value
    return values


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def data_url(path: Path) -> str:
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if not mime.startswith("image/"):
        raise ValueError(f"unsupported reference type: {path.name}")
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode('ascii')}"


def resolve_job(raw: str) -> Path:
    job = Path(raw)
    if not job.is_absolute():
        job = ROOT / job
    job = job.resolve(strict=True)
    job.relative_to(ROOT)
    for required in ("request-config.json", "prompt.md"):
        if not (job / required).is_file():
            raise SystemExit(f"Missing {required} in {job}")
    return job


def submit(job: Path) -> int:
    config = json.loads((job / "request-config.json").read_text(encoding="utf-8"))
    env = load_dotenv(ROOT / ".env.local")
    missing = [key for key in ("ARK_BASE_URL", "ARK_API_KEY_BAK") if not env.get(key)]
    if missing:
        raise SystemExit("Missing required configuration keys: " + ", ".join(missing))
    attempt_path = job / "submit-attempt.json"
    if attempt_path.exists():
        raise SystemExit("Submission marker already exists. Refusing a second attempt.")

    prompt_path = job / "prompt.md"
    output_path = (job / config["output"]).resolve(strict=False)
    output_path.relative_to(job)
    references: list[str] = []
    reference_evidence: list[dict[str, object]] = []
    for item in config["references"]:
        path = (job / item["path"]).resolve(strict=True)
        path.relative_to(ROOT)
        references.append(data_url(path))
        reference_evidence.append({
            "path": path.relative_to(ROOT).as_posix(),
            "role": item["role"],
            "sha256": sha256(path),
        })

    marker: dict[str, object] = {
        "schema": 1,
        "requestStartedEpoch": int(time.time()),
        "automaticRetries": 0,
        "credentialSource": ".env.local:ARK_API_KEY_BAK",
        "outcome": "request-started",
        "model": config["model"],
        "promptSha256": sha256(prompt_path),
        "requestConfigSha256": sha256(job / "request-config.json"),
        "references": reference_evidence,
    }
    write_json(attempt_path, marker)

    payload = {
        "model": config["model"],
        "prompt": prompt_path.read_text(encoding="utf-8"),
        "image": references,
        "size": config.get("size", "2K"),
        "output_format": config.get("outputFormat", "png"),
        "response_format": "url",
        "watermark": False,
    }
    endpoint = env["ARK_BASE_URL"].rstrip("/")
    if endpoint.endswith("/images/generations"):
        pass
    elif endpoint.endswith("/api/v3"):
        endpoint += "/images/generations"
    else:
        endpoint += "/api/v3/images/generations"
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {env['ARK_API_KEY_BAK']}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            status = response.status
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            error_body: object = json.loads(raw)
        except json.JSONDecodeError:
            error_body = raw
        marker.update({
            "outcome": "http-error",
            "httpStatus": error.code,
            "errorBodySha256": hashlib.sha256(raw.encode()).hexdigest(),
            "errorBody": error_body,
        })
        write_json(attempt_path, marker)
        print(json.dumps({"outcome": "http-error", "httpStatus": error.code}))
        return 3
    except Exception as error:
        marker.update({"outcome": "request-outcome-unknown", "errorType": type(error).__name__})
        write_json(attempt_path, marker)
        print(json.dumps(marker, ensure_ascii=False))
        return 4

    data = body.get("data") or []
    url = data[0].get("url") if data else None
    if status != 200 or not url:
        marker.update({"outcome": "invalid-success-response", "httpStatus": status})
        write_json(attempt_path, marker)
        print(json.dumps(marker, ensure_ascii=False))
        return 5

    marker.update({
        "outcome": "generation-succeeded-download-started",
        "httpStatus": status,
        "requestId": body.get("request_id"),
        "created": body.get("created"),
        "usage": body.get("usage"),
    })
    write_json(attempt_path, marker)
    try:
        with urllib.request.urlopen(url, timeout=240) as response:
            output_path.write_bytes(response.read())
    except Exception as error:
        marker.update({"outcome": "generation-succeeded-download-unknown", "errorType": type(error).__name__})
        write_json(attempt_path, marker)
        print(json.dumps(marker, ensure_ascii=False))
        return 6

    marker.update({
        "outcome": "succeeded",
        "output": output_path.relative_to(job).as_posix(),
        "outputSha256": sha256(output_path),
        "outputBytes": output_path.stat().st_size,
    })
    write_json(attempt_path, marker)
    response_record = {
        "receivedAtEpoch": int(time.time()),
        "httpStatus": status,
        "requestId": body.get("request_id"),
        "model": config["model"],
        "created": body.get("created"),
        "usage": body.get("usage"),
        "output": output_path.relative_to(job).as_posix(),
        "outputSha256": marker["outputSha256"],
        "outputBytes": marker["outputBytes"],
        "automaticRetries": 0,
    }
    write_json(job / "response.json", response_record)
    print(json.dumps(marker, ensure_ascii=False))
    return 0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["submit"])
    parser.add_argument("job")
    args = parser.parse_args()
    job = resolve_job(args.job)
    raise SystemExit(submit(job))


if __name__ == "__main__":
    main()
