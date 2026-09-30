#!/usr/bin/env python3

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any
from urllib.parse import urlsplit

import laya_mlx as laya


MAX_REQUEST_SIZE = 2 * 1024 * 1024


class LayaServer(HTTPServer):
    def __init__(
        self,
        server_address: tuple[str, int],
        model: str,
        dtype: str,
        device: str,
    ) -> None:
        super().__init__(server_address, LayaHandler)

        self.model_name = model
        self.dtype = dtype
        self.device = device

        print(
            f"dotfiles-laya: loading {model} (dtype={dtype}, device={device})",
            file=sys.stderr,
            flush=True,
        )

        self.agent = laya.load(
            model,
            dtype=dtype,
            device=device,
        )

        print(
            f"dotfiles-laya: listening on "
            f"http://{server_address[0]}:{server_address[1]}",
            file=sys.stderr,
            flush=True,
        )


class LayaHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    @property
    def laya_server(self) -> LayaServer:
        return self.server  # type: ignore[return-value]

    def send_json(self, status: int, payload: Any) -> None:
        body = json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status: int, message: str) -> None:
        self.send_json(
            status,
            {
                "error": message,
            },
        )

    def read_json(self) -> Any:
        length = self.headers.get("Content-Length")

        if length is None:
            raise ValueError("missing Content-Length")

        try:
            size = int(length)
        except ValueError as error:
            raise ValueError("invalid Content-Length") from error

        if size < 0:
            raise ValueError("invalid Content-Length")

        if size > MAX_REQUEST_SIZE:
            raise ValueError(f"request body exceeds {MAX_REQUEST_SIZE} bytes")

        body = self.rfile.read(size)

        try:
            return json.loads(body)
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid JSON: {error.msg}") from error

    def do_GET(self) -> None:
        path = urlsplit(self.path).path

        if path == "/health":
            self.send_json(
                200,
                {
                    "status": "ok",
                },
            )
            return

        if path == "/info":
            self.send_json(
                200,
                {
                    "model": self.laya_server.model_name,
                    "dtype": self.laya_server.dtype,
                    "device": self.laya_server.device,
                },
            )
            return

        self.send_error_json(404, "not found")

    def do_POST(self) -> None:
        path = urlsplit(self.path).path

        if path != "/predict":
            self.send_error_json(404, "not found")
            return

        try:
            request = self.read_json()

            if not isinstance(request, dict):
                raise ValueError("request must be a JSON object")

            if "state" not in request:
                raise ValueError("missing state")

            if "questions" not in request:
                raise ValueError("missing questions")

            questions = request["questions"]

            if not isinstance(questions, dict):
                raise ValueError("questions must be a JSON object")

            result = self.laya_server.agent.predict(
                request["state"],
                questions,
            )

            self.send_json(200, result)
        except ValueError as error:
            self.send_error_json(400, str(error))
        except Exception as error:
            print(
                f"dotfiles-laya: prediction failed: {error}",
                file=sys.stderr,
                flush=True,
            )
            self.send_error_json(
                500,
                f"{type(error).__name__}: {error}",
            )

    def log_message(self, format: str, *args: Any) -> None:
        print(
            f"dotfiles-laya: {format % args}",
            file=sys.stderr,
            flush=True,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--host",
        default="127.0.0.1",
    )

    parser.add_argument(
        "--port",
        type=int,
        default=18081,
    )

    parser.add_argument(
        "--model",
        required=True,
    )

    parser.add_argument(
        "--dtype",
        default="float16",
    )

    parser.add_argument(
        "--device",
        default="gpu",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    server = LayaServer(
        (args.host, args.port),
        model=args.model,
        dtype=args.dtype,
        device=args.device,
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
