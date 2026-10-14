"""Tiny Cube REST client for the sl_test checks.

Signs short-lived HS256 tokens with the secret from CUBEJS_API_SECRET. The secret and
the tokens are never printed or written anywhere.
"""
import base64
import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.request

BASE = os.environ.get("CUBE_URL", "http://localhost:4000") + "/cubejs-api/v1"


def _b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def token(claims=None, secret=None, ttl=300):
    secret = secret if secret is not None else os.environ["CUBEJS_API_SECRET"]
    payload = dict(claims or {})
    payload["exp"] = int(time.time()) + ttl
    head = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = _b64(json.dumps(payload).encode())
    sig = _b64(hmac.new(secret.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest())
    return f"{head}.{body}.{sig}"


def call(path, tok, body=None, timeout=120):
    """Return (http_status, parsed_json). Retries 'Continue wait' replies."""
    for _ in range(30):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(BASE + path, data=data, method="POST" if data else "GET",
                                     headers={"Authorization": tok or "", "Content-Type": "application/json"})
        try:
            r = urllib.request.urlopen(req, timeout=timeout)
            status, js = r.status, json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            status = e.code
            try:
                js = json.loads(e.read().decode() or "{}")
            except ValueError:
                js = {}
        if isinstance(js, dict) and js.get("error") == "Continue wait":
            time.sleep(1)
            continue
        return status, js
    return 408, {"error": "timed out waiting for Cube"}


def load(query, tok):
    return call("/load", tok, {"query": query})


def meta(tok):
    return call("/meta", tok)
