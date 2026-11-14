#!/usr/bin/env python3
"""Keep only the local OAuth bridge cookie in an agent-browser checkpoint."""

import json
import os
import stat
import sys
import tempfile
from pathlib import Path


COOKIE_NAME = "__Host-oauth_bridge"


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON object key")
        result[key] = value
    return result


def _reject_constant(_value):
    raise ValueError("invalid JSON constant")


def normalize_checkpoint(checkpoint):
    path = Path(checkpoint)
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError("checkpoint is not a regular file")

    with path.open(encoding="utf-8") as source:
        payload = json.load(
            source,
            object_pairs_hook=_unique_object,
            parse_constant=_reject_constant,
        )

    if not isinstance(payload, dict):
        raise ValueError("invalid checkpoint")
    cookies = payload.get("cookies")
    if not isinstance(cookies, list) or not isinstance(payload.get("origins"), list):
        raise ValueError("invalid checkpoint")

    candidates = []
    for cookie in cookies:
        if not isinstance(cookie, dict):
            raise ValueError("invalid cookie")
        name = cookie.get("name")
        domain = cookie.get("domain")
        if not isinstance(name, str) or not isinstance(domain, str):
            raise ValueError("invalid cookie")
        if name == COOKIE_NAME and domain == "localhost":
            candidates.append(cookie)

    if len(candidates) != 1:
        raise ValueError("expected one OAuth bridge cookie")
    cookie = candidates[0]
    if (
        cookie.get("path") != "/"
        or cookie.get("secure") is not True
        or cookie.get("httpOnly") is not True
        or not isinstance(cookie.get("value"), str)
        or not cookie["value"]
    ):
        raise ValueError("invalid OAuth bridge cookie")

    normalized = {"cookies": [cookie], "origins": []}
    temporary_path = None
    descriptor = None
    try:
        descriptor, temporary_path = tempfile.mkstemp(
            dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
        )
        os.fchmod(descriptor, 0o600)
        output = os.fdopen(descriptor, "w", encoding="utf-8")
        descriptor = None
        with output:
            json.dump(normalized, output, separators=(",", ":"), allow_nan=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if temporary_path is not None:
            try:
                os.unlink(temporary_path)
            except FileNotFoundError:
                pass


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        print("clean-auth-state: expected one checkpoint path", file=sys.stderr)
        return 2
    try:
        normalize_checkpoint(args[0])
    except Exception:
        print("clean-auth-state: failed", file=sys.stderr)
        return 1
    print("clean-auth-state: normalized")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
