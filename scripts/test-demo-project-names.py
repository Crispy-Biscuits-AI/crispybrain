#!/usr/bin/env python3

from __future__ import annotations

import importlib
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
demo_server = importlib.import_module("demo.server")


class RecordingUpstreamHandler(BaseHTTPRequestHandler):
    received_payloads: list[dict[str, object]] = []

    def log_message(self, fmt: str, *args: object) -> None:
        return

    def do_POST(self) -> None:
        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length) if content_length else b"{}"
        payload = json.loads(raw_body.decode("utf-8"))
        self.__class__.received_payloads.append(payload)

        body = json.dumps(
            {
                "ok": True,
                "answer": "Test answer",
                "project_slug": payload.get("project_slug"),
                "selected_sources": [],
                "retrieved_candidates": [],
            }
        ).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def start_server(handler: type[BaseHTTPRequestHandler]) -> tuple[ThreadingHTTPServer, str]:
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address
    return server, f"http://{host}:{port}"


def request_json(method: str, url: str, payload: dict[str, object] | None = None) -> tuple[int, dict[str, object]]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


class ProjectDisplayNameTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)

        self.original_inbox_dir = demo_server.INBOX_DIR
        self.original_upstream_url = demo_server.UPSTREAM_URL
        demo_server.INBOX_DIR = Path(self.tempdir.name) / "inbox"
        demo_server.INBOX_DIR.mkdir(parents=True)
        (demo_server.INBOX_DIR / "alpha").mkdir()

        RecordingUpstreamHandler.received_payloads = []
        self.upstream_server, upstream_url = start_server(RecordingUpstreamHandler)
        self.addCleanup(self.upstream_server.shutdown)
        self.addCleanup(self.upstream_server.server_close)
        demo_server.UPSTREAM_URL = upstream_url

        self.demo_httpd, self.base_url = start_server(demo_server.CrispyBrainDemoHandler)
        self.addCleanup(self.demo_httpd.shutdown)
        self.addCleanup(self.demo_httpd.server_close)

    def tearDown(self) -> None:
        demo_server.INBOX_DIR = self.original_inbox_dir
        demo_server.UPSTREAM_URL = self.original_upstream_url

    def test_create_query_and_delete_project_with_display_name(self) -> None:
        status, created = request_json("POST", f"{self.base_url}/api/projects", {"project_name": "Star Wars"})
        self.assertEqual(status, HTTPStatus.CREATED)
        self.assertEqual(created["ok"], True)
        self.assertEqual(created["created_project_display_name"], "Star Wars")
        project_slug = created["created_project_slug"]
        self.assertIsInstance(project_slug, str)
        self.assertNotEqual(project_slug, "Star Wars")
        self.assertTrue((demo_server.INBOX_DIR / project_slug).is_dir())

        option = next(option for option in created["project_options"] if option["project_slug"] == project_slug)
        self.assertEqual(option["display_name"], "Star Wars")
        self.assertEqual(created["selected_project_slug"], project_slug)

        status, answer = request_json(
            "POST",
            f"{self.base_url}/api/demo/ask",
            {"question": "Who is Darth Vader?", "project_slug": project_slug},
        )
        self.assertEqual(status, HTTPStatus.OK)
        self.assertEqual(answer["ok"], True)
        self.assertEqual(RecordingUpstreamHandler.received_payloads[-1]["project_slug"], project_slug)

        status, deleted = request_json("DELETE", f"{self.base_url}/api/projects/{project_slug}")
        self.assertEqual(status, HTTPStatus.OK)
        self.assertEqual(deleted["ok"], True)
        self.assertEqual(deleted["deleted_project_slug"], project_slug)
        self.assertEqual(deleted["deleted_project_display_name"], "Star Wars")
        self.assertFalse((demo_server.INBOX_DIR / project_slug).exists())
        self.assertNotIn(project_slug, deleted["projects"])

    def test_duplicate_display_name_variants_are_rejected(self) -> None:
        first_status, first = request_json("POST", f"{self.base_url}/api/projects", {"project_name": "Star Wars"})
        self.assertEqual(first_status, HTTPStatus.CREATED)

        for duplicate_name in [" star wars ", "STAR WARS"]:
            status, body = request_json("POST", f"{self.base_url}/api/projects", {"project_name": duplicate_name})
            self.assertEqual(status, HTTPStatus.CONFLICT)
            self.assertEqual(body["error"]["code"], "PROJECT_ALREADY_EXISTS")

    def test_existing_lowercase_slug_project_still_lists_queries_and_deletes(self) -> None:
        status, projects = request_json("GET", f"{self.base_url}/api/projects")
        self.assertEqual(status, HTTPStatus.OK)
        self.assertIn("alpha", projects["projects"])
        alpha_option = next(option for option in projects["project_options"] if option["project_slug"] == "alpha")
        self.assertEqual(alpha_option["display_name"], "alpha")

        status, answer = request_json(
            "POST",
            f"{self.base_url}/api/demo/ask",
            {"question": "What is alpha?", "project_slug": "alpha"},
        )
        self.assertEqual(status, HTTPStatus.OK)
        self.assertEqual(answer["ok"], True)
        self.assertEqual(RecordingUpstreamHandler.received_payloads[-1]["project_slug"], "alpha")

        status, deleted = request_json("DELETE", f"{self.base_url}/api/projects/alpha")
        self.assertEqual(status, HTTPStatus.OK)
        self.assertNotIn("alpha", deleted["projects"])

    def test_invalid_project_names_are_rejected(self) -> None:
        invalid_names = ["", "   ", "../alpha", "alpha/beta", r"alpha\beta"]
        for project_name in invalid_names:
            with self.subTest(project_name=project_name):
                status, body = request_json("POST", f"{self.base_url}/api/projects", {"project_name": project_name})
                self.assertEqual(status, HTTPStatus.BAD_REQUEST)
                self.assertIn(body["error"]["code"], {"EMPTY_PROJECT_NAME", "INVALID_PROJECT_NAME"})


if __name__ == "__main__":
    unittest.main()
