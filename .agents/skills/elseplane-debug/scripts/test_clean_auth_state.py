import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).with_name("clean-auth-state.py")
SPEC = importlib.util.spec_from_file_location("clean_auth_state", SCRIPT)
clean_auth_state = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(clean_auth_state)


def oauth_cookie(**changes):
    cookie = {
        "name": "__Host-oauth_bridge",
        "value": "synthetic-cookie-value",
        "domain": "localhost",
        "path": "/",
        "secure": True,
        "httpOnly": True,
        "sameSite": "Lax",
        "expires": 1900000000,
        "session": False,
        "futureMetadata": {"retained": True},
    }
    cookie.update(changes)
    return cookie


def checkpoint(cookies=None, origins=None):
    return {
        "cookies": [oauth_cookie()] if cookies is None else cookies,
        "origins": [] if origins is None else origins,
    }


class CleanAuthStateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "auth-state.json"

    def write_json(self, payload):
        self.path.write_text(json.dumps(payload), encoding="utf-8")

    def assert_rejected_unchanged(self, contents):
        self.path.write_bytes(contents)
        with self.assertRaises((ValueError, OSError)):
            clean_auth_state.normalize_checkpoint(self.path)
        self.assertEqual(self.path.read_bytes(), contents)

    def test_filters_everything_except_cookie_and_discards_origins(self):
        retained = oauth_cookie()
        source = checkpoint(
            cookies=[
                {"name": "session", "domain": ".github.com", "value": "synthetic"},
                {"name": "dartAppInstanceId", "domain": "localhost", "value": "synthetic"},
                retained,
            ],
            origins=[
                {
                    "origin": "http://localhost:3002",
                    "localStorage": [
                        {"name": "dartAppInstanceId", "value": "synthetic"}
                    ],
                },
                {"origin": "https://github.com", "localStorage": []},
            ],
        )
        self.write_json(source)

        clean_auth_state.normalize_checkpoint(self.path)

        result = json.loads(self.path.read_text(encoding="utf-8"))
        self.assertEqual(result, {"cookies": [retained], "origins": []})
        self.assertEqual(set(result), {"cookies", "origins"})

    def test_normalization_is_idempotent_and_file_is_private(self):
        self.write_json(checkpoint())
        self.path.chmod(0o644)

        clean_auth_state.normalize_checkpoint(self.path)
        once = self.path.read_bytes()
        clean_auth_state.normalize_checkpoint(self.path)

        self.assertEqual(self.path.read_bytes(), once)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)

    def test_malformed_and_ambiguous_checkpoints_remain_unchanged(self):
        invalid_payloads = [
            b"{not json",
            b'{"cookies": [], "cookies": [], "origins": []}',
            json.dumps([]).encode(),
            json.dumps({"origins": []}).encode(),
            json.dumps({"cookies": {}, "origins": []}).encode(),
            json.dumps({"cookies": [], "origins": {}}).encode(),
            json.dumps(checkpoint(cookies=["not a cookie"])).encode(),
            json.dumps(checkpoint(cookies=[{"name": "unshaped"}])).encode(),
            json.dumps(checkpoint(cookies=[])).encode(),
            json.dumps(checkpoint(cookies=[oauth_cookie(), oauth_cookie()])).encode(),
        ]
        for contents in invalid_payloads:
            with self.subTest(contents=contents):
                self.assert_rejected_unchanged(contents)

    def test_invalid_bridge_cookie_attributes_remain_unchanged(self):
        for changes in (
            {"path": "/other"},
            {"secure": False},
            {"secure": 1},
            {"httpOnly": False},
            {"value": ""},
            {"value": None},
        ):
            with self.subTest(changes=changes):
                contents = json.dumps(checkpoint(cookies=[oauth_cookie(**changes)])).encode()
                self.assert_rejected_unchanged(contents)

    def test_rejects_symlink_without_changing_target(self):
        target = Path(self.directory.name) / "target.json"
        target.write_text(json.dumps(checkpoint()), encoding="utf-8")
        link = Path(self.directory.name) / "link.json"
        link.symlink_to(target)
        original = target.read_bytes()

        with self.assertRaises(ValueError):
            clean_auth_state.normalize_checkpoint(link)

        self.assertTrue(link.is_symlink())
        self.assertEqual(target.read_bytes(), original)

    def test_write_failure_preserves_original_and_removes_temporary_file(self):
        original = json.dumps(checkpoint()).encode()
        self.path.write_bytes(original)

        def fail_after_partial_write(_payload, output, **_kwargs):
            output.write("partial")
            raise OSError("synthetic write failure")

        with mock.patch.object(clean_auth_state.json, "dump", fail_after_partial_write):
            with self.assertRaises(OSError):
                clean_auth_state.normalize_checkpoint(self.path)

        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(list(Path(self.directory.name).iterdir()), [self.path])

    def test_replace_failure_preserves_original_and_removes_temporary_file(self):
        original = json.dumps(checkpoint()).encode()
        self.path.write_bytes(original)

        with mock.patch.object(clean_auth_state.os, "replace", side_effect=OSError):
            with self.assertRaises(OSError):
                clean_auth_state.normalize_checkpoint(self.path)

        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(list(Path(self.directory.name).iterdir()), [self.path])

    def test_overflowed_json_number_fails_without_replacing_checkpoint(self):
        contents = (
            json.dumps(checkpoint())
            .replace('"expires": 1900000000', '"expires": 1e9999')
            .replace('"synthetic-cookie-value"', '"synthetic-private-marker"')
            .encode()
        )
        self.path.write_bytes(contents)

        with self.assertRaises(ValueError):
            clean_auth_state.normalize_checkpoint(self.path)

        self.assertEqual(self.path.read_bytes(), contents)
        self.assertEqual(list(Path(self.directory.name).iterdir()), [self.path])

        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.path)],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "clean-auth-state: failed\n")
        self.assertNotIn("synthetic-private-marker", result.stderr)
        self.assertEqual(self.path.read_bytes(), contents)
        self.assertEqual(list(Path(self.directory.name).iterdir()), [self.path])

    def test_cli_failure_is_generic_and_does_not_echo_checkpoint_contents(self):
        self.path.write_text("synthetic-private-marker", encoding="utf-8")
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.path)],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "clean-auth-state: failed\n")
        self.assertNotIn("synthetic-private-marker", result.stderr)


if __name__ == "__main__":
    unittest.main()
