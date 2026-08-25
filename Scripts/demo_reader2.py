#!/usr/bin/env python3
"""demo_reader2.py — sirve DOS eventos de demostración (para probar la UX
del stack de múltiples preguntas). Pane IDs FICTICIOS (demo:*) — no toca
ningún harness real. Reemplaza temporalmente al reader en el puerto 8900."""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEMO = {
    "events": [
        {
            "agent": "codex",
            "pane_id": "demo:1",
            "status": "blocked",
            "question": "Database migration\nHow should we handle the users table migration for the new tenant_id column?\n\u2771 1. Additive migration (Recommended)\n     Create the column as nullable, backfill in a transaction, then set NOT NULL.\n  2. Blue/green table swap\n     Create the new table, dual-write, switch reads, drop the old one.\n  3. Type something.",
            "context": {"cwd": "/tmp/demo-migration",
                        "terminal_title": "users-migration"}
        },
        {
            "agent": "pi",
            "pane_id": "demo:2",
            "status": "blocked",
            "question": "API design\nShould the new /v2/workspaces endpoint require the legal-entity header on every call?\n\u2771 1. Require on each request (Recommended)\n     Always present and validate; no hidden state.\n  2. Derive from token\n     Read the legal-entity from the JWT claims instead.\n  3. Type something.",
            "context": {"cwd": "/tmp/demo-api",
                        "terminal_title": "api-design"}
        }
    ]
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps(DEMO).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8900
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"demo_reader2 en :{port}", flush=True)
    srv.serve_forever()
