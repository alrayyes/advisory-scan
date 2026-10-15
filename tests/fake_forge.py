#!/usr/bin/env python3
"""A fake GitHub/Forgejo issues API for the scan-mode tests.

Usage: fake_forge.py <state.json> <requests.jsonl> <port file>

state.json holds {"issues": [...], "fail": {"METHOD /path": status},
"respond": {"METHOD /path": any JSON}}: "fail" answers with that status,
"respond" answers 200 with that body instead of the real one. The
server keeps issues in memory, writes the state back after each write so a
test can read the end result, and appends every request it gets to
requests.jsonl: method, path, query, Authorization header, parsed body.
Paths may carry Forgejo's /api/v1 prefix; it's stripped before routing.
Standard library only, so the tests need nothing but python3.
"""

import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

STATE_PATH, LOG_PATH, PORT_PATH = sys.argv[1:4]
with open(STATE_PATH) as f:
    STATE = json.load(f)
STATE.setdefault("issues", [])
STATE.setdefault("fail", {})
STATE.setdefault("respond", {})


def save():
    with open(STATE_PATH, "w") as f:
        json.dump(STATE, f)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def handle_any(self, method):
        url = urlparse(self.path)
        path = re.sub(r"^/api/v1", "", url.path)
        query = {k: v[0] for k, v in parse_qs(url.query).items()}
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw) if raw else None
        with open(LOG_PATH, "a") as f:
            f.write(json.dumps({
                "method": method,
                "path": path,
                "prefix": url.path != path,
                "query": query,
                "auth": self.headers.get("Authorization"),
                "body": body,
            }) + "\n")

        failure = STATE["fail"].get(f"{method} {path}")
        if failure:
            return self.reply(failure, {"message": "injected failure"})
        if f"{method} {path}" in STATE["respond"]:
            return self.reply(200, STATE["respond"][f"{method} {path}"])

        m = re.fullmatch(r"/repos/[^/]+/[^/]+/issues", path)
        if m and method == "GET":
            return self.list_issues(query)
        if m and method == "POST":
            number = max([i["number"] for i in STATE["issues"]] + [0]) + 1
            issue = {"number": number, "state": "open", "labels": [],
                     "comments": [], **body}
            STATE["issues"].append(issue)
            save()
            return self.reply(201, issue)

        m = re.fullmatch(r"/repos/[^/]+/[^/]+/issues/(\d+)(/comments|/labels)?", path)
        if m:
            issue = next((i for i in STATE["issues"]
                          if i["number"] == int(m.group(1))), None)
            if issue is None:
                return self.reply(404, {"message": "not found"})
            if m.group(2) is None and method == "PATCH":
                issue.update(body)
            elif m.group(2) == "/comments" and method == "POST":
                issue["comments"].append(body["body"])
            elif m.group(2) == "/labels" and method == "POST":
                issue["labels"] += body["labels"]
            else:
                return self.reply(405, {"message": "method not allowed"})
            save()
            return self.reply(201 if method == "POST" else 200, issue)

        return self.reply(404, {"message": "no route"})

    def list_issues(self, query):
        size = int(query.get("per_page") or query.get("limit") or 30)
        # A server-side cap, like Forgejo's MAX_RESPONSE_ITEMS.
        size = min(size, STATE.get("max_page", size))
        page = int(query.get("page") or 1)
        state = query.get("state", "open")
        items = [i for i in STATE["issues"] if i["state"] == state]
        if query.get("type") == "issues":
            items = [i for i in items if "pull_request" not in i]
        return self.reply(200, items[(page - 1) * size:page * size])

    def reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PATCH(self):
        self.handle_any("PATCH")


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_PATH, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
