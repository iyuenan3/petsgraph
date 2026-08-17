#!/usr/bin/env python3
"""Submit or poll one recorded Seedance endpoint job without automatic retries."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TERMINAL = {"succeeded", "failed", "cancelled", "expired"}
PETSDESK_ENV = Path("/Users/maxwell/Desktop/Projects/petsdesk/.env.local")


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


def image_part(path: Path, role: str) -> dict[str, object]:
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return {
        "type": "image_url",
        "image_url": {"url": f"data:{mime};base64,{encoded}"},
        "role": role,
    }


def video_part(url: str, role: str) -> dict[str, object]:
    return {
        "type": "video_url",
        "video_url": {"url": url},
        "role": role,
    }


def storage_configuration(env: dict[str, str]) -> dict[str, str]:
    fallback = load_dotenv(PETSDESK_ENV) if PETSDESK_ENV.is_file() else {}
    values = dict(env)
    for key in ("TOS_ENDPOINT", "TOS_REGION", "TOS_BUCKET"):
        if not values.get(key) and fallback.get(key):
            values[key] = fallback[key]
    required = (
        "TOS_ACCESS_KEY_ID",
        "TOS_SECRET_ACCESS_KEY",
        "TOS_ENDPOINT",
        "TOS_REGION",
        "TOS_BUCKET",
    )
    missing = [key for key in required if not values.get(key)]
    if missing:
        raise RuntimeError("Missing required TOS configuration keys: " + ", ".join(missing))
    return values


def tos_client(env: dict[str, str]):
    try:
        import tos
    except ImportError as error:
        raise RuntimeError(
            "Video references require the official TOS SDK; install package 'tos' in the task runtime"
        ) from error
    return tos, tos.TosClientV2(
        env["TOS_ACCESS_KEY_ID"],
        env["TOS_SECRET_ACCESS_KEY"],
        env["TOS_ENDPOINT"],
        env["TOS_REGION"],
    )


def upload_temporary_video(
    env: dict[str, str], path: Path, object_key: str
) -> str:
    tos, client = tos_client(env)
    try:
        with path.open("rb") as stream:
            client.put_object(
                env["TOS_BUCKET"],
                object_key,
                content=stream,
                content_type=mimetypes.guess_type(path.name)[0] or "video/mp4",
            )
        head = client.head_object(env["TOS_BUCKET"], object_key)
        if int(head.content_length) != path.stat().st_size:
            raise RuntimeError("Uploaded video reference size mismatch")
        signed = client.pre_signed_url(
            tos.HttpMethodType.Http_Method_Get,
            env["TOS_BUCKET"],
            object_key,
            expires=7200,
        )
        return signed.signed_url
    finally:
        client.close()


def cleanup_temporary_inputs(env: dict[str, str], marker: dict[str, object]) -> None:
    temporary = marker.get("temporaryInputs") or []
    if not temporary:
        return
    storage = storage_configuration(env)
    for item in temporary:
        if item.get("cleanup") == "deleted-and-verified":
            continue
        tos, client = tos_client(storage)
        try:
            client.delete_object(storage["TOS_BUCKET"], item["objectKey"])
            try:
                client.head_object(storage["TOS_BUCKET"], item["objectKey"])
            except tos.exceptions.TosServerError as error:
                if error.status_code == 404:
                    item["cleanup"] = "deleted-and-verified"
                    continue
                raise
            raise RuntimeError("Temporary TOS input still exists after delete")
        finally:
            client.close()


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


def configuration(job: Path) -> tuple[dict[str, object], dict[str, str]]:
    config = json.loads((job / "request-config.json").read_text(encoding="utf-8"))
    env = load_dotenv(ROOT / ".env.local")
    missing = [key for key in ("ARK_BASE_URL", "ARK_API_KEY") if not env.get(key)]
    if missing:
        raise SystemExit("Missing required configuration keys: " + ", ".join(missing))
    return config, env


def submit(job: Path) -> int:
    config, env = configuration(job)
    attempt_path = job / "submit-attempt.json"
    if attempt_path.exists():
        raise SystemExit("Submission marker already exists. Refusing a second attempt.")
    prompt = (job / "prompt.md").read_text(encoding="utf-8")
    action_root = job.parent
    resolved_references = []
    reference_evidence = []
    for item in config["references"]:
        path = (action_root / item["path"]).resolve(strict=True)
        path.relative_to(ROOT)
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        if not (mime.startswith("image/") or mime.startswith("video/")):
            raise SystemExit(f"Unsupported Seedance reference type: {path.name}")
        resolved_references.append((path, item["role"], mime))
        reference_evidence.append({
            "path": str(path.relative_to(ROOT)),
            "role": item["role"],
            "mimeType": mime,
            "sha256": sha256(path),
        })
    marker = {
        "schema": 1,
        "requestStartedEpoch": int(time.time()),
        "automaticRetries": 0,
        "outcome": "request-started",
        "model": config["model"],
        "promptSha256": sha256(job / "prompt.md"),
        "requestConfigSha256": sha256(job / "request-config.json"),
        "references": reference_evidence,
        "temporaryInputs": [],
    }
    write_json(attempt_path, marker)
    references = []
    try:
        for path, role, mime in resolved_references:
            if mime.startswith("image/"):
                references.append(image_part(path, role))
                continue
            storage = storage_configuration(env)
            operation = f"{job.name}-{uuid.uuid4()}"
            object_key = f"petsgraph/seedance-inputs/{job.parent.name}/{operation}{path.suffix.lower()}"
            temporary = {
                "objectKey": object_key,
                "path": str(path.relative_to(ROOT)),
                "sha256": sha256(path),
                "bytes": path.stat().st_size,
                "cleanup": "upload-started",
            }
            marker["temporaryInputs"].append(temporary)
            write_json(attempt_path, marker)
            signed_url = upload_temporary_video(storage, path, object_key)
            temporary["cleanup"] = "awaiting-task-terminal"
            write_json(attempt_path, marker)
            references.append(video_part(signed_url, role))
    except Exception as error:
        marker["outcome"] = "upload-error"
        marker["errorType"] = type(error).__name__
        try:
            cleanup_temporary_inputs(env, marker)
        except Exception as cleanup_error:
            marker["cleanupErrorType"] = type(cleanup_error).__name__
        write_json(attempt_path, marker)
        print(json.dumps({"outcome": "upload-error", "errorType": type(error).__name__}))
        return 4
    payload = {
        "model": config["model"],
        "content": [{"type": "text", "text": prompt}] + references,
        "generate_audio": False,
        "ratio": config["ratio"],
        "duration": config["durationSeconds"],
        "resolution": config["resolution"],
        "return_last_frame": True,
        "watermark": False,
    }
    endpoint = env["ARK_BASE_URL"].rstrip("/") + "/contents/generations/tasks"
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {env['ARK_API_KEY']}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            status = response.status
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            error_body: object = json.loads(raw)
        except json.JSONDecodeError:
            error_body = {"message": raw[:1000]}
        write_json(job / "submit-response.json", {"httpStatus": error.code, "error": error_body})
        marker.update({"outcome": "http-error", "httpStatus": error.code})
        try:
            cleanup_temporary_inputs(env, marker)
        except Exception as cleanup_error:
            marker["cleanupErrorType"] = type(cleanup_error).__name__
        write_json(attempt_path, marker)
        print(json.dumps({"outcome": "http-error", "httpStatus": error.code}))
        return 2
    except Exception as error:
        marker.update({"outcome": "result-unknown", "errorType": type(error).__name__})
        for item in marker["temporaryInputs"]:
            item["cleanup"] = "retained-result-unknown"
        write_json(attempt_path, marker)
        print(json.dumps({"outcome": "result-unknown", "errorType": type(error).__name__}))
        return 3
    write_json(job / "submit-response.json", body)
    task_id = body.get("id")
    marker.update({"outcome": "created", "httpStatus": status, "taskId": task_id})
    write_json(attempt_path, marker)
    print(json.dumps({"outcome": "created", "httpStatus": status, "taskId": task_id}))
    return 0


def download(url: str, path: Path) -> dict[str, object]:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".partial")
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(urllib.request.Request(url, method="GET"), timeout=180) as response, temporary.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
            digest.update(chunk)
            size += len(chunk)
    temporary.replace(path)
    return {"path": str(path.relative_to(path.parents[1])), "bytes": size, "sha256": digest.hexdigest()}


def poll(job: Path) -> int:
    config, env = configuration(job)
    attempt = json.loads((job / "submit-attempt.json").read_text(encoding="utf-8"))
    task_id = attempt.get("taskId")
    if attempt.get("outcome") != "created" or not task_id:
        raise SystemExit("Job does not have a confirmed created task ID. Refusing to guess or resubmit.")
    endpoint = env["ARK_BASE_URL"].rstrip("/") + f"/contents/generations/tasks/{task_id}"
    headers = {"Authorization": f"Bearer {env['ARK_API_KEY']}"}
    while True:
        with urllib.request.urlopen(urllib.request.Request(endpoint, headers=headers, method="GET"), timeout=120) as response:
            body = json.loads(response.read().decode("utf-8"))
        status = str(body.get("status", "unknown"))
        with (job / "poll.jsonl").open("a", encoding="utf-8") as log:
            log.write(json.dumps({"epoch": int(time.time()), "status": status}) + "\n")
        print(json.dumps({"taskId": task_id, "status": status}), flush=True)
        if status in TERMINAL:
            break
        time.sleep(20)
    if status != "succeeded":
        write_json(job / "task-result.json", body)
        try:
            cleanup_temporary_inputs(env, attempt)
        finally:
            write_json(job / "submit-attempt.json", attempt)
        return 2
    content = body.get("content") or {}
    video_url = content.get("video_url")
    last_frame_url = content.get("last_frame_url")
    if not video_url:
        raise RuntimeError("Task succeeded without a video URL")
    stem = config["artifactStem"]
    video = download(video_url, job / "artifacts" / f"{stem}.mp4")
    last_frame = download(last_frame_url, job / "artifacts" / f"{stem}-last-frame.png") if last_frame_url else None
    safe_body = dict(body)
    safe_content = dict(content)
    safe_content["video_url"] = "[redacted-after-download]"
    if last_frame_url:
        safe_content["last_frame_url"] = "[redacted-after-download]"
    safe_body["content"] = safe_content
    safe_body["downloaded"] = {"video": video, "lastFrame": last_frame}
    write_json(job / "task-result.json", safe_body)
    try:
        cleanup_temporary_inputs(env, attempt)
    finally:
        write_json(job / "submit-attempt.json", attempt)
    print(json.dumps({"status": "downloaded", "video": video, "lastFrame": last_frame}), flush=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("submit", "poll"))
    parser.add_argument("job")
    args = parser.parse_args()
    job = resolve_job(args.job)
    return submit(job) if args.command == "submit" else poll(job)


if __name__ == "__main__":
    raise SystemExit(main())
