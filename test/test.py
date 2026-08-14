
""" Compare patched nginx against nginx:1.25-bookworm over a few HTTP cases. """
from __future__ import annotations

import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASELINE = os.environ.get("BASELINE_IMAGE", "nginx:1.25-bookworm")
PATCHED = os.environ.get("PATCHED_IMAGE", "nginx-patched:1.25-bookworm")
ROOT = Path(__file__).resolve().parent
CUSTOM_CONF = ROOT / "config" / "nginx.conf"

SKIP_HEADERS = {"date", "connection", "keep-alive"}


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs)


def image_exists(name: str) -> bool:
    out = run(["docker", "images", "-q", name]).stdout.strip()
    return bool(out)


def start_container(image: str, extra_args: list[str] | None = None) -> str:
    cmd = [
        "docker",
        "run",
        "-d",
        "--rm",
        "-p",
        "127.0.0.1::80",
        * (extra_args or []),
        image,
    ]
    cid = run(cmd).stdout.strip()
    return cid


def mapped_port(cid: str) -> int:
    out = run(["docker", "port", cid, "80"]).stdout.strip()
    # 127.0.0.1:32789 or [::]:32789
    return int(out.rsplit(":", 1)[1])


def wait_ready(port: int, timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    last_err: Exception | None = None
    while time.time() < deadline:
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=1)
            return
        except Exception as exc:  # nginx may 404 later; connection refused is the wait
            last_err = exc
            if isinstance(exc, urllib.error.HTTPError):
                return
            time.sleep(0.2)
    raise RuntimeError(f"nginx on port {port} did not become ready: {last_err}")


def stop_container(cid: str) -> None:
    subprocess.run(["docker", "rm", "-f", cid], capture_output=True)


def http_get(port: int, path: str, method: str = "GET", body: bytes | None = None, headers: dict[str, str] | None = None):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        data=body,
        method=method,
        headers=headers or {},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read()


def raw_request(port: int, payload: bytes):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        sock.sendall(payload)
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    raw = b"".join(chunks)
    header_blob, _, body = raw.partition(b"\r\n\r\n")
    lines = header_blob.split(b"\r\n")
    status = None
    parts = lines[0].split()
    if len(parts) >= 2 and parts[1].isdigit():
        status = int(parts[1])
    headers = {}
    for line in lines[1:]:
        if b":" not in line:
            continue
        key, value = line.split(b":", 1)
        headers[key.decode("latin1")] = value.decode("latin1").strip()
    return status, headers, body


def normalize_headers(headers: dict) -> dict[str, str]:
    return {
        k.lower(): v
        for k, v in headers.items()
        if k.lower() not in SKIP_HEADERS
    }


def compare(name: str, left, right) -> None:
    ls, lh, lb = left
    rs, rh, rb = right
    if ls != rs:
        raise SystemExit(f"FAIL {name}: status {ls} vs {rs}")
    if lb != rb:
        raise SystemExit(
            f"FAIL {name}: body mismatch ({len(lb)} vs {len(rb)} bytes)"
        )
    lh_n, rh_n = normalize_headers(lh), normalize_headers(rh)
    if lh_n != rh_n:
        raise SystemExit(f"FAIL {name}: headers {lh_n} vs {rh_n}")
    print(f"OK   {name}  (status {ls})")


def run_suite(port_a: int, port_b: int, cases: list) -> None:
    for name, fn in cases:
        compare(name, fn(port_a), fn(port_b))


def default_cases():
    big = b"x" * (256 * 1024)
    too_big = b"x" * (2 * 1024 * 1024)

    def get_root(port):
        return http_get(port, "/")

    def get_missing(port):
        return http_get(port, "/definitely-not-here")

    def head_root(port):
        return http_get(port, "/", method="HEAD")

    def post_large(port):
        return http_get(port, "/", method="POST", body=big)

    def post_too_large(port):
        return http_get(port, "/", method="POST", body=too_big)

    def malformed(port):
        # HTTP/1.1 with no Host header → 400 on both stock and patched nginx.
        return raw_request(port, b"GET / HTTP/1.1\r\n\r\n")

    return [
        ("GET /", get_root),
        ("GET missing path", get_missing),
        ("HEAD /", head_root),
        ("POST 256KiB body", post_large),
        ("POST 2MiB body (over client_max_body_size)", post_too_large),
        ("malformed request (HTTP/1.1, no Host)", malformed),
    ]


def custom_cases():
    def get_root(port):
        return http_get(port, "/")

    def get_health(port):
        return http_get(port, "/health")

    return [
        ("custom config GET /", get_root),
        ("custom config GET /health", get_health),
    ]


def main() -> int:
    for img in (BASELINE, PATCHED):
        if not image_exists(img):
            print(f"missing image: {img}", file=sys.stderr)
            print("build the patched image first: make image", file=sys.stderr)
            return 1

    ids: list[str] = []
    try:
        print(f"comparing {PATCHED} to {BASELINE}")

        a = start_container(BASELINE)
        b = start_container(PATCHED)
        ids.extend([a, b])
        pa, pb = mapped_port(a), mapped_port(b)
        wait_ready(pa)
        wait_ready(pb)
        run_suite(pa, pb, default_cases())

        mount = f"{CUSTOM_CONF}:/etc/nginx/conf.d/default.conf:ro"
        a2 = start_container(BASELINE, ["-v", mount])
        b2 = start_container(PATCHED, ["-v", mount])
        ids.extend([a2, b2])
        pa2, pb2 = mapped_port(a2), mapped_port(b2)
        wait_ready(pa2)
        wait_ready(pb2)
        run_suite(pa2, pb2, custom_cases())
    finally:
        for cid in ids:
            stop_container(cid)

    print("all cases matched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
