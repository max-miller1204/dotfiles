#!/usr/bin/env python3
"""Exercise the Nix-owned stdio language servers as a Claude-like LSP client."""

from __future__ import annotations

import json
import os
import select
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


def message(payload: dict[str, Any]) -> bytes:
    body = json.dumps(payload, separators=(",", ":")).encode()
    return f"Content-Length: {len(body)}\r\n\r\n".encode() + body


class LspClient:
    def __init__(self, command: str) -> None:
        environment = os.environ.copy()
        environment.pop("NODE_PATH", None)
        self.command = command
        # A stderr PIPE is inherited by grandchildren (typescript-language-server
        # forks tsserver), so its write end can outlive the server and a read on
        # it never returns, while a full 64 KiB pipe buffer would deadlock the
        # server itself. A temporary file has neither failure mode.
        self.stderr_file = tempfile.TemporaryFile()
        self.process = subprocess.Popen(
            [command, "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.stderr_file,
            env=environment,
        )
        if self.process.stdin is None or self.process.stdout is None:
            raise RuntimeError(f"failed to open stdio pipes for {command}")
        self.stdin = self.process.stdin
        self.stdout = self.process.stdout
        self.buffer = bytearray()

    def __enter__(self) -> LspClient:
        return self

    def __exit__(self, *_exception: object) -> None:
        self.terminate()

    def stderr_text(self) -> str:
        self.stderr_file.seek(0)
        return self.stderr_file.read().decode(errors="replace")

    def send(self, payload: dict[str, Any]) -> None:
        self.stdin.write(message(payload))
        self.stdin.flush()

    def read_more(self, deadline: float) -> None:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([self.stdout], [], [], remaining)[0]:
            raise TimeoutError(f"timed out waiting for {self.command}")
        chunk = os.read(self.stdout.fileno(), 65536)
        if not chunk:
            raise RuntimeError(f"{self.command} closed stdout: {self.stderr_text()}")
        self.buffer.extend(chunk)

    def read_message(self, deadline: float) -> dict[str, Any]:
        separator = b"\r\n\r\n"
        while separator not in self.buffer:
            self.read_more(deadline)
        header, remainder = bytes(self.buffer).split(separator, 1)
        headers = {}
        for line in header.split(b"\r\n"):
            name, value = line.decode().split(":", 1)
            headers[name.lower()] = value.strip()
        try:
            length = int(headers["content-length"])
        except (KeyError, ValueError) as error:
            raise RuntimeError(f"invalid LSP Content-Length: {headers!r}") from error
        while len(remainder) < length:
            self.read_more(deadline)
            _, remainder = bytes(self.buffer).split(separator, 1)
        body = remainder[:length]
        self.buffer = bytearray(remainder[length:])
        try:
            decoded = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise RuntimeError(f"invalid LSP response body: {body!r}") from error
        if not isinstance(decoded, dict):
            raise RuntimeError(f"LSP response is not an object: {decoded!r}")
        return decoded

    def request(
        self, request_id: int, method: str, params: dict[str, Any] | None
    ) -> dict[str, Any]:
        self.send(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params,
            }
        )
        deadline = time.monotonic() + 30
        while True:
            response = self.read_message(deadline)
            if response.get("id") == request_id and "method" not in response:
                return response
            if "id" in response and "method" in response:
                self.send({"jsonrpc": "2.0", "id": response["id"], "result": None})

    def notify(self, method: str, params: dict[str, Any] | None) -> None:
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def close(self) -> None:
        self.notify("exit", None)
        self.stdin.close()
        try:
            return_code = self.process.wait(timeout=10)
        except subprocess.TimeoutExpired as error:
            self.process.kill()
            raise RuntimeError(f"{self.command} did not exit after shutdown") from error
        if return_code != 0:
            raise RuntimeError(
                f"{self.command} exited {return_code}: {self.stderr_text()}"
            )

    def terminate(self) -> None:
        """Release the server and its pipes on every path, including failures."""
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait(timeout=10)
        for stream in (self.process.stdin, self.process.stdout):
            if stream is not None and not stream.closed:
                stream.close()
        self.stderr_file.close()


def run_server(command: str, language: str, filename: str, source: str) -> None:
    with tempfile.TemporaryDirectory(prefix=f"dotfiles-{language}-lsp-") as temp:
        root = Path(temp)
        document = root / filename
        document.write_text(source)
        root_uri = root.as_uri()
        document_uri = document.as_uri()
        # Every assertion and timeout below must still release the server, or a
        # failed unsandboxed run leaves an orphaned process holding the pipes.
        with LspClient(command) as client:
            initialize = client.request(
                1,
                "initialize",
                {
                    "processId": None,
                    "clientInfo": {"name": "Claude Code", "version": "smoke"},
                    "rootUri": root_uri,
                    "capabilities": {},
                    "workspaceFolders": [{"uri": root_uri, "name": root.name}],
                },
            )
            if "error" in initialize or "capabilities" not in initialize.get(
                "result", {}
            ):
                raise RuntimeError(f"{command} initialization failed: {initialize!r}")
            client.notify("initialized", {})
            client.notify(
                "textDocument/didOpen",
                {
                    "textDocument": {
                        "uri": document_uri,
                        "languageId": language,
                        "version": 1,
                        "text": source,
                    }
                },
            )
            hover = client.request(
                2,
                "textDocument/hover",
                {
                    "textDocument": {"uri": document_uri},
                    "position": {"line": 0, "character": 6},
                },
            )
            if "error" in hover or hover.get("result") is None:
                raise RuntimeError(f"{command} hover failed: {hover!r}")
            shutdown = client.request(3, "shutdown", None)
            if "error" in shutdown or shutdown.get("result", "missing") is not None:
                raise RuntimeError(f"{command} shutdown failed: {shutdown!r}")
            client.close()


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: lsp-smoke.py PYRIGHT_LANGSERVER TYPESCRIPT_LANGUAGE_SERVER"
        )
    run_server(sys.argv[1], "python", "fixture.py", "answer: int = 42\n")
    run_server(sys.argv[2], "typescript", "fixture.ts", "const answer: number = 42;\n")
    print("Pyright and TypeScript LSP startup, hover, and shutdown passed")


if __name__ == "__main__":
    main()
