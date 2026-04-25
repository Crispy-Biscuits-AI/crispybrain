#!/usr/bin/env python3

from __future__ import annotations

import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse


REPO_ROOT = Path(__file__).resolve().parent.parent
DEMO_DIR = REPO_ROOT / "demo"
ASSETS_DIR = REPO_ROOT / "assets"
INBOX_DIR = REPO_ROOT / "inbox"
HOST = os.environ.get("CRISPYBRAIN_DEMO_HOST", "127.0.0.1")
PORT = int(os.environ.get("CRISPYBRAIN_DEMO_PORT", "8787"))
UPSTREAM_URL = os.environ.get(
    "CRISPYBRAIN_DEMO_WEBHOOK_URL",
    "http://localhost:5678/webhook/crispybrain-demo",
)
REQUEST_TIMEOUT_SECONDS = float(os.environ.get("CRISPYBRAIN_DEMO_TIMEOUT_SECONDS", "60"))
APP_VERSION_ENV_VAR = "CRISPYBRAIN_APP_VERSION"
APP_VERSION_PLACEHOLDER = "__CRISPYBRAIN_APP_VERSION__"
UNKNOWN_VERSION = "unknown-version"
FOOTER_VERSION_PATTERN = re.compile(r'(<span class="footer-version">)(.*?)(</span>)', re.DOTALL)
PROJECT_SLUG_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
PROJECT_NAME_METADATA_FILE = ".crispybrain-projects.json"
PROJECT_NAME_CONTROL_PATTERN = re.compile(r"[\x00-\x1f\x7f]")
INBOX_IMPORT_FILENAME_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._ -]{0,127}")
PROJECT_DISPLAY_NAME_VALIDATION_MESSAGE = (
    "Project names may contain letters, numbers, spaces, hyphens, and underscores, but not slashes, path traversal, or control characters."
)
PROJECT_SLUG_VALIDATION_MESSAGE = "Project references must use a safe inbox project slug."


def run_git_command(*args: str) -> str | None:
    try:
        completed = subprocess.run(
            ["git", *args],
            cwd=REPO_ROOT,
            capture_output=True,
            check=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None

    value = completed.stdout.strip()
    return value or None


def resolve_injected_app_version() -> str | None:
    version = os.environ.get(APP_VERSION_ENV_VAR)
    if not version:
        return None

    normalized = version.strip()
    return normalized or None


def resolve_runtime_context() -> str:
    if Path("/.dockerenv").exists():
        return "docker"

    cgroup_path = Path("/proc/1/cgroup")
    try:
        cgroup_text = cgroup_path.read_text(encoding="utf-8")
    except OSError:
        return "local"

    if "docker" in cgroup_text or "containerd" in cgroup_text:
        return "docker"

    return "local"


def resolve_repo_version() -> str:
    injected_version = resolve_injected_app_version()
    if injected_version:
        return injected_version

    command_sets = (
        ("describe", "--tags", "--always"),
        ("rev-parse", "--short", "HEAD"),
    )
    for command in command_sets:
        version = run_git_command(*command)
        if version:
            return version

    runtime = resolve_runtime_context()
    if runtime == "docker":
        return f"{UNKNOWN_VERSION} ({runtime})"

    return UNKNOWN_VERSION


def resolve_commit_hash() -> str:
    return run_git_command("rev-parse", "--short", "HEAD") or UNKNOWN_VERSION


def resolve_footer_version() -> str:
    return resolve_repo_version()


def list_inbox_projects() -> list[str]:
    if not INBOX_DIR.exists():
        return []

    return sorted(
        entry.name
        for entry in INBOX_DIR.iterdir()
        if entry.is_dir() and not entry.name.startswith(".")
    )


def load_project_metadata() -> dict[str, Any]:
    metadata_path = INBOX_DIR / PROJECT_NAME_METADATA_FILE
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"projects": {}}

    if not isinstance(metadata, dict) or not isinstance(metadata.get("projects"), dict):
        return {"projects": {}}

    return metadata


def save_project_metadata(metadata: dict[str, Any]) -> None:
    INBOX_DIR.mkdir(parents=True, exist_ok=True)
    metadata_path = INBOX_DIR / PROJECT_NAME_METADATA_FILE
    projects_metadata = metadata.get("projects")
    if not isinstance(projects_metadata, dict) or not projects_metadata:
        try:
            metadata_path.unlink()
        except FileNotFoundError:
            pass
        return

    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def get_project_display_name(project_slug: str, metadata: dict[str, Any] | None = None) -> str:
    metadata = metadata or load_project_metadata()
    project_metadata = metadata.get("projects", {}).get(project_slug)
    if isinstance(project_metadata, dict):
        display_name = project_metadata.get("display_name")
        if isinstance(display_name, str) and display_name.strip():
            return display_name.strip()

    return project_slug


def build_project_options(project_slugs: list[str]) -> list[dict[str, str]]:
    metadata = load_project_metadata()
    return [
        {
            "project_slug": project_slug,
            "display_name": get_project_display_name(project_slug, metadata),
        }
        for project_slug in project_slugs
    ]


def resolve_default_project_slug(project_slugs: list[str]) -> str:
    if "alpha" in project_slugs:
        return "alpha"
    if project_slugs:
        return project_slugs[0]
    return ""


def build_projects_payload() -> dict[str, Any]:
    project_slugs = list_inbox_projects()
    return {
        "projects": project_slugs,
        "project_options": build_project_options(project_slugs),
        "default_project_slug": resolve_default_project_slug(project_slugs),
    }


def validate_project_display_name(project_name: str) -> tuple[str | None, str | None]:
    normalized_name = project_name.strip()
    if not normalized_name:
        return None, "EMPTY_PROJECT_NAME"
    if PROJECT_NAME_CONTROL_PATTERN.search(normalized_name):
        return None, "INVALID_PROJECT_NAME"
    if "/" in normalized_name or "\\" in normalized_name:
        return None, "INVALID_PROJECT_NAME"
    if ".." in normalized_name.split():
        return None, "INVALID_PROJECT_NAME"
    if ".." in normalized_name:
        return None, "INVALID_PROJECT_NAME"
    if not re.fullmatch(r"[A-Za-z0-9 _-]+", normalized_name):
        return None, "INVALID_PROJECT_NAME"

    return normalized_name, None


def normalize_project_display_name_for_comparison(project_name: str) -> str:
    return re.sub(r"\s+", " ", project_name.strip()).casefold()


def project_display_name_exists(project_name: str) -> bool:
    desired_name = normalize_project_display_name_for_comparison(project_name)
    metadata = load_project_metadata()
    return any(
        normalize_project_display_name_for_comparison(get_project_display_name(project_slug, metadata)) == desired_name
        for project_slug in list_inbox_projects()
    )


def slugify_project_display_name(project_name: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9_-]+", "-", project_name.strip()).strip("-_").lower()
    slug = re.sub(r"-{2,}", "-", slug)
    return slug or "project"


def build_available_project_slug(project_name: str) -> str:
    base_slug = slugify_project_display_name(project_name)
    project_slugs = set(list_inbox_projects())
    if base_slug not in project_slugs:
        return base_slug

    suffix = 2
    while f"{base_slug}-{suffix}" in project_slugs:
        suffix += 1

    return f"{base_slug}-{suffix}"


def resolve_project_path(project_slug: str) -> Path | None:
    normalized_slug = project_slug.strip()
    if not PROJECT_SLUG_PATTERN.fullmatch(normalized_slug):
        return None

    candidate = (INBOX_DIR / normalized_slug).resolve()
    try:
        candidate.relative_to(INBOX_DIR.resolve())
    except ValueError:
        return None

    if candidate == INBOX_DIR.resolve():
        return None

    return candidate


def validate_inbox_import_filename(filename: Any) -> tuple[str | None, str | None]:
    if not isinstance(filename, str):
        return None, "filename must be a string"

    if not filename:
        return None, "filename must not be empty"

    if filename != filename.strip():
        return None, "filename must not contain leading or trailing whitespace"

    if not filename:
        return None, "filename must not be empty"

    candidate_path = Path(filename)
    if candidate_path.is_absolute():
        return None, "absolute paths are not allowed"

    if "/" in filename or "\\" in filename:
        return None, "subdirectories and path separators are not allowed"

    if filename in {".", ".."} or ".." in filename.split("."):
        return None, "path traversal is not allowed"

    if filename.startswith("."):
        return None, "hidden filenames are not allowed"

    if filename.endswith(".") or filename.endswith(" "):
        return None, "filename must not end with a dot or space"

    if not INBOX_IMPORT_FILENAME_PATTERN.fullmatch(filename):
        return None, "filename may contain only letters, numbers, spaces, dots, hyphens, and underscores"

    return filename, None


def render_index_html() -> str:
    footer_version = html.escape(resolve_footer_version())
    rendered = (DEMO_DIR / "index.html").read_text(encoding="utf-8")
    if APP_VERSION_PLACEHOLDER in rendered:
        return rendered.replace(APP_VERSION_PLACEHOLDER, footer_version)

    def replace_footer_version(match: re.Match[str]) -> str:
        return f"{match.group(1)}{footer_version}{match.group(3)}"

    rendered, _ = FOOTER_VERSION_PATTERN.subn(replace_footer_version, rendered, count=1)
    return rendered


class CrispyBrainDemoHandler(SimpleHTTPRequestHandler):
    server_version = "CrispyBrainDemo/0.2"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stdout.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), fmt % args))
        sys.stdout.flush()

    def do_GET(self) -> None:
        clean_path = urlparse(self.path).path
        if clean_path == "/api/projects":
            self._write_json(
                HTTPStatus.OK,
                build_projects_payload(),
            )
            return
        if clean_path == "/meta":
            self._write_json(
                HTTPStatus.OK,
                {
                    "version": resolve_repo_version(),
                    "runtime": resolve_runtime_context(),
                    "commit": resolve_commit_hash(),
                },
            )
            return
        if self._maybe_serve_index(include_body=True):
            return
        super().do_GET()

    def do_HEAD(self) -> None:
        if self._maybe_serve_index(include_body=False):
            return
        super().do_HEAD()

    def do_DELETE(self) -> None:
        clean_path = urlparse(self.path).path
        prefix = "/api/projects/"
        if not clean_path.startswith(prefix):
            self.send_error(HTTPStatus.NOT_FOUND, "Unknown endpoint")
            return

        encoded_slug = clean_path.removeprefix(prefix)
        project_slug = unquote(encoded_slug).strip()
        project_path = resolve_project_path(project_slug)
        if project_path is None:
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": {
                        "code": "INVALID_PROJECT_SLUG",
                        "message": PROJECT_SLUG_VALIDATION_MESSAGE,
                    },
                },
            )
            return

        if not project_path.exists() or not project_path.is_dir():
            self._write_json(
                HTTPStatus.NOT_FOUND,
                {
                    "ok": False,
                    "error": {
                        "code": "PROJECT_NOT_FOUND",
                        "message": "The requested inbox project does not exist.",
                    },
                },
            )
            return

        deleted_project_display_name = get_project_display_name(project_slug)
        shutil.rmtree(project_path)
        metadata = load_project_metadata()
        projects_metadata = metadata.get("projects")
        if isinstance(projects_metadata, dict) and project_slug in projects_metadata:
            projects_metadata.pop(project_slug, None)
            save_project_metadata(metadata)

        response_payload = build_projects_payload()
        response_payload.update(
            {
                "ok": True,
                "deleted_project_slug": project_slug,
                "deleted_project_display_name": deleted_project_display_name,
            }
        )
        self._write_json(HTTPStatus.OK, response_payload)

    def do_POST(self) -> None:
        clean_path = urlparse(self.path).path
        if clean_path not in {"/api/demo/ask", "/api/projects", "/api/inbox/import"}:
            self.send_error(HTTPStatus.NOT_FOUND, "Unknown endpoint")
            return

        payload = self._read_json_payload()
        if payload is None:
            return

        if clean_path == "/api/projects":
            self._handle_create_project(payload)
            return

        if clean_path == "/api/inbox/import":
            self._handle_inbox_import(payload)
            return

        question = payload.get("question")
        project_slug = payload.get("project_slug")
        session_id = payload.get("session_id")

        if not isinstance(question, str) or not question.strip():
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": {
                        "code": "INVALID_QUESTION",
                        "message": "Please enter a question before submitting the demo.",
                    },
                },
            )
            return

        if project_slug is not None and not isinstance(project_slug, str):
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": {
                        "code": "INVALID_PROJECT_SLUG",
                        "message": "project_slug must be a string when provided.",
                    },
                },
            )
            return

        if session_id is not None and not isinstance(session_id, str):
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": {
                        "code": "INVALID_SESSION_ID",
                        "message": "session_id must be a string when provided.",
                    },
                },
            )
            return

        request_payload = {
            "question": question.strip(),
            "project_slug": (project_slug or "").strip() or "alpha",
        }
        if isinstance(session_id, str) and session_id.strip():
            request_payload["session_id"] = session_id.strip()

        encoded_body = json.dumps(request_payload).encode("utf-8")
        upstream_request = urllib.request.Request(
            UPSTREAM_URL,
            data=encoded_body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        started_at = time.perf_counter()
        try:
            with urllib.request.urlopen(upstream_request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                upstream_status = response.status
                upstream_bytes = response.read()
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            self._write_json(
                HTTPStatus.BAD_GATEWAY,
                {
                    "ok": False,
                    "error": {
                        "code": "N8N_HTTP_ERROR",
                        "message": "The demo proxy reached n8n but got an unexpected HTTP response.",
                        "status": exc.code,
                        "details": body[:400],
                    },
                },
            )
            return
        except urllib.error.URLError as exc:
            self._write_json(
                HTTPStatus.BAD_GATEWAY,
                {
                    "ok": False,
                    "error": {
                        "code": "N8N_UNAVAILABLE",
                        "message": "The demo proxy could not reach the n8n demo workflow.",
                        "details": str(exc.reason),
                    },
                },
            )
            return

        elapsed_ms = round((time.perf_counter() - started_at) * 1000)

        try:
            upstream_payload = json.loads(upstream_bytes.decode("utf-8"))
        except json.JSONDecodeError:
            self._write_json(
                HTTPStatus.BAD_GATEWAY,
                {
                    "ok": False,
                    "error": {
                        "code": "INVALID_UPSTREAM_JSON",
                        "message": "The n8n demo workflow returned a non-JSON response.",
                    },
                },
            )
            return

        if isinstance(upstream_payload, dict):
            debug = upstream_payload.get("debug")
            if isinstance(debug, dict):
                debug["proxy_duration_ms"] = elapsed_ms
                debug["proxy_endpoint"] = self.path
                debug["upstream_url"] = UPSTREAM_URL
                debug["upstream_status"] = upstream_status
            else:
                upstream_payload["debug"] = {
                    "proxy_duration_ms": elapsed_ms,
                    "proxy_endpoint": clean_path,
                    "upstream_url": UPSTREAM_URL,
                    "upstream_status": upstream_status,
                }

        status = HTTPStatus.OK if upstream_status < 500 else HTTPStatus.BAD_GATEWAY
        self._write_json(status, upstream_payload)

    def _handle_create_project(self, payload: dict[str, Any]) -> None:
        project_name = payload.get("project_name", payload.get("project_slug"))
        if not isinstance(project_name, str):
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": {
                        "code": "INVALID_PROJECT_NAME",
                        "message": "project_name must be a string.",
                    },
                },
            )
            return

        display_name, validation_error = validate_project_display_name(project_name)
        if validation_error == "EMPTY_PROJECT_NAME":
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": {
                        "code": "EMPTY_PROJECT_NAME",
                        "message": "Enter a project name before creating a project.",
                    },
                },
            )
            return
        if validation_error or display_name is None:
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": {
                        "code": "INVALID_PROJECT_NAME",
                        "message": PROJECT_DISPLAY_NAME_VALIDATION_MESSAGE,
                    },
                },
            )
            return

        INBOX_DIR.mkdir(parents=True, exist_ok=True)
        if project_display_name_exists(display_name):
            self._write_json(
                HTTPStatus.CONFLICT,
                {
                    "ok": False,
                    "error": {
                        "code": "PROJECT_ALREADY_EXISTS",
                        "message": "An inbox project with that name already exists.",
                    },
                },
            )
            return

        normalized_slug = build_available_project_slug(display_name)
        project_path = resolve_project_path(normalized_slug)
        if project_path is None:
            self._write_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {
                    "ok": False,
                    "error": {
                        "code": "PROJECT_CREATE_FAILED",
                        "message": "CrispyBrain could not create a safe project reference for that name.",
                    },
                },
            )
            return

        if project_path.exists():
            self._write_json(
                HTTPStatus.CONFLICT,
                {
                    "ok": False,
                    "error": {
                        "code": "PROJECT_ALREADY_EXISTS",
                        "message": "An inbox project with that slug already exists.",
                    },
                },
            )
            return

        try:
            project_path.mkdir(exist_ok=False)
        except FileExistsError:
            self._write_json(
                HTTPStatus.CONFLICT,
                {
                    "ok": False,
                    "error": {
                        "code": "PROJECT_ALREADY_EXISTS",
                        "message": "An inbox project with that slug already exists.",
                    },
                },
            )
            return
        except OSError as exc:
            self._write_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {
                    "ok": False,
                    "error": {
                        "code": "PROJECT_CREATE_FAILED",
                        "message": "CrispyBrain could not create the requested inbox project.",
                        "details": str(exc),
                    },
                },
            )
            return

        metadata = load_project_metadata()
        projects_metadata = metadata.setdefault("projects", {})
        if isinstance(projects_metadata, dict):
            projects_metadata[normalized_slug] = {"display_name": display_name}
            save_project_metadata(metadata)

        response_payload = build_projects_payload()
        response_payload.update(
            {
                "ok": True,
                "created_project_slug": normalized_slug,
                "created_project_display_name": display_name,
                "selected_project_slug": normalized_slug,
                "selected_project_display_name": display_name,
            }
        )
        self._write_json(HTTPStatus.CREATED, response_payload)

    def _handle_inbox_import(self, payload: dict[str, Any]) -> None:
        files = payload.get("files")
        if not isinstance(files, list) or not files:
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "success": False,
                    "saved": [],
                    "rejected": [{"reason": "files must be a non-empty array"}],
                    "inbox_path": "inbox",
                },
            )
            return

        saved: list[dict[str, Any]] = []
        rejected: list[dict[str, Any]] = []
        inbox_root = INBOX_DIR.resolve()

        for index, file_payload in enumerate(files):
            if not isinstance(file_payload, dict):
                rejected.append(
                    {
                        "index": index,
                        "filename": None,
                        "reason": "file entry must be an object",
                    }
                )
                continue

            original_filename = file_payload.get("filename")
            filename, filename_error = validate_inbox_import_filename(original_filename)
            if filename_error or filename is None:
                rejected.append(
                    {
                        "index": index,
                        "filename": original_filename,
                        "reason": filename_error,
                    }
                )
                continue

            content = file_payload.get("content")
            if not isinstance(content, str):
                rejected.append(
                    {
                        "index": index,
                        "filename": filename,
                        "reason": "content must be a string",
                    }
                )
                continue

            target_path = (INBOX_DIR / filename).resolve()
            try:
                target_path.relative_to(inbox_root)
            except ValueError:
                rejected.append(
                    {
                        "index": index,
                        "filename": filename,
                        "reason": "resolved path escapes inbox",
                    }
                )
                continue

            encoded_content = content.encode("utf-8")
            try:
                INBOX_DIR.mkdir(parents=True, exist_ok=True)
                with target_path.open("xb") as inbox_file:
                    inbox_file.write(encoded_content)
            except FileExistsError:
                rejected.append(
                    {
                        "index": index,
                        "filename": filename,
                        "reason": "file already exists",
                    }
                )
                continue
            except OSError as exc:
                rejected.append(
                    {
                        "index": index,
                        "filename": filename,
                        "reason": f"could not save file: {exc}",
                    }
                )
                continue

            timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            saved.append(
                {
                    "filename": filename,
                    "path": f"inbox/{filename}",
                    "bytes": len(encoded_content),
                    "timestamp": timestamp,
                }
            )

        response_payload = {
            "success": not rejected,
            "saved": saved,
            "rejected": rejected,
            "inbox_path": "inbox",
        }
        if saved and rejected:
            status = HTTPStatus.MULTI_STATUS
        elif saved:
            status = HTTPStatus.CREATED
        elif any(item.get("reason") == "file already exists" for item in rejected):
            status = HTTPStatus.CONFLICT
        else:
            status = HTTPStatus.BAD_REQUEST

        self._write_json(status, response_payload)

    def translate_path(self, path: str) -> str:
        clean_path = urlparse(path).path
        if clean_path in ("/", ""):
            return str(DEMO_DIR / "index.html")
        if clean_path.startswith("/assets/"):
            relative = clean_path.removeprefix("/assets/")
            return str(ASSETS_DIR / relative)
        relative = clean_path.lstrip("/")
        return str(DEMO_DIR / relative)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _write_json(self, status: HTTPStatus, payload: Any) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json_payload(self) -> dict[str, Any] | None:
        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length) if content_length else b""
        try:
            payload = json.loads(raw_body.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": {
                        "code": "INVALID_JSON",
                        "message": "Request body must be valid JSON.",
                    },
                },
            )
            return None

        if not isinstance(payload, dict):
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": {
                        "code": "INVALID_JSON",
                        "message": "Request body must be a JSON object.",
                    },
                },
            )
            return None

        return payload

    def _maybe_serve_index(self, include_body: bool) -> bool:
        clean_path = urlparse(self.path).path
        if clean_path not in ("/", "", "/index.html"):
            return False

        body = render_index_html().encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if include_body:
            self.wfile.write(body)
        return True


def main() -> None:
    if not DEMO_DIR.exists():
        raise SystemExit(f"Demo directory is missing: {DEMO_DIR}")

    httpd = ThreadingHTTPServer((HOST, PORT), CrispyBrainDemoHandler)
    display_host = "localhost" if HOST in {"127.0.0.1", "0.0.0.0"} else HOST
    print(f"CrispyBrain demo server listening on http://{display_host}:{PORT}")
    print(f"Proxying demo requests to {UPSTREAM_URL}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping CrispyBrain demo server")
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
