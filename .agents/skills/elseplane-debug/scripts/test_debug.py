import contextlib
import io
import json
import os
import socket
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import debug


class DebugLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        self.root_patch = mock.patch.object(debug, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.info = debug.task_info("shape-resize")
        self.alive = False
        self.marker = None
        self.pane_command = "make"
        self.commands = []
        self.invoke_patch = mock.patch.object(debug, "invoke", side_effect=self.fake_invoke)
        self.invoke_patch.start()
        self.addCleanup(self.invoke_patch.stop)

    def fake_invoke(self, args, timeout=5):
        self.commands.append(args)
        code, output = 0, ""
        if args[:3] == ["tmux", "has-session", "-t"]:
            code = 0 if self.alive else 1
        elif args[:2] == ["tmux", "new-session"]:
            self.alive = True
        elif args[:2] == ["tmux", "set-option"] and args[-2] == "@elseplane-owner":
            self.marker = args[-1]
        elif args[:2] == ["tmux", "show-option"]:
            output = (self.marker or "") + "\n"
        elif args[:2] == ["tmux", "display-message"]:
            output = f"{self.info['session']} 0 0 {self.pane_command}\n"
        elif args[:2] == ["tmux", "send-keys"]:
            if "q" in args:
                self.alive = False
            elif args[-1] == "C-m" and not ("-l" in args):
                uri = self.info["run_dir"] / "vm-service.uri"
                uri.write_text("ws://private-debug-token\n", encoding="utf-8")
                uri.chmod(0o600)
        return subprocess.CompletedProcess(args, code, output, "")

    def test_port_free_reports_unused_and_time_wait_ports_free(self):
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            unused_port = reservation.getsockname()[1]
        self.assertTrue(debug.port_free(unused_port))

        with socket.socket() as listener, socket.socket() as client:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.settimeout(2)
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            port = listener.getsockname()[1]
            self.assertFalse(debug.port_free(port))

            client.settimeout(2)
            client.connect(("127.0.0.1", port))
            connection, _ = listener.accept()
            with connection:
                connection.close()
                self.assertEqual(client.recv(1), b"")

        self.assertTrue(debug.port_free(port))

    def make_owner(self):
        directory = self.info["run_dir"]
        directory.mkdir(parents=True, mode=0o700)
        directory.chmod(0o700)
        (directory / "flutter.log").touch(mode=0o600)
        owner = {key: str(value) if isinstance(value, Path) else value for key, value in self.info.items()}
        owner["token"] = "a" * 64
        debug.create_private_file(directory / "owner.json", owner)
        self.alive = True
        self.marker = owner["token"]
        return owner

    def test_task_is_required_and_a_lowercase_slug(self):
        for value in (None, "Shape", "", "a" * 49, "bad/task"):
            with self.subTest(value=value), self.assertRaises(debug.DebugError) as caught:
                debug.task_info(value)
            self.assertEqual(caught.exception.code, "missing_task" if not value else "invalid_task")

    def test_make_command_quotes_spaces_quotes_and_dollars_across_make(self):
        marker = Path(self.temp.name) / "SHOULD_NOT_EXIST"
        unusual_root = Path(self.temp.name) / f"repo 'quoted' $literal; touch {marker}"
        info = debug.task_info("safe-task")
        info["root"] = str(unusual_root)
        info["run_dir"] = unusual_root / "local-mediator" / "debug" / "safe-task"
        command = debug.flutter_command(info["run_dir"] / "vm-service.uri")
        fake_bin = Path(self.temp.name) / "bin"
        fake_bin.mkdir()
        fake_make = fake_bin / "make"
        fake_make.write_text(
            "#!/usr/bin/python3\n"
            "import subprocess, sys\n"
            "value = sys.argv[-1].split('=', 1)[1].replace('$$', '$')\n"
            "result = subprocess.run(['/bin/sh', '-c', \"printf '%s\\\\n' \" + value], text=True, capture_output=True)\n"
            "sys.stdout.write(result.stdout)\n"
            "sys.exit(result.returncode)\n",
            encoding="utf-8",
        )
        fake_make.chmod(0o700)
        env = dict(os.environ, PATH=f"{fake_bin}:/usr/bin:/bin")
        result = subprocess.run(["/bin/sh", "-c", command], env=env, text=True, capture_output=True, check=True)
        args = result.stdout.splitlines()
        self.assertEqual(args[:3], ["--web-run-headless", "--web-browser-debug-port=3004", "--web-browser-flag=--incognito"])
        self.assertEqual(args[3], f"--vmservice-out-file={info['run_dir'] / 'vm-service.uri'}")
        self.assertFalse(marker.exists())

    @mock.patch.object(debug.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}")
    @mock.patch.object(debug, "port_free", return_value=True)
    @mock.patch.object(debug, "health_reachable", return_value=True)
    @mock.patch.object(debug, "cdp_has_page", return_value=True)
    def test_start_is_private_and_status_never_prints_secrets(self, _cdp, _health, _ports, _which):
        payload = debug.start(self.info)
        directory = self.info["run_dir"]
        self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual((directory / "flutter.log").stat().st_mode & 0o777, 0o600)
        self.assertEqual((directory / "owner.json").stat().st_mode & 0o777, 0o600)
        owner = json.loads((directory / "owner.json").read_text(encoding="utf-8"))
        self.assertEqual(payload["state"], "ready")
        self.assertEqual(payload["ui_readiness"], "unchecked")
        self.assertEqual(payload["auth"], "not_restored")
        self.assertNotIn(owner["token"], json.dumps(payload))
        self.assertNotIn("private-debug-token", json.dumps(payload))
        status_payload = debug.status(self.info)
        self.assertEqual(status_payload["state"], "ready")
        self.assertTrue(status_payload["artifacts"]["vm_service_uri_file"])
        self.assertNotIn(owner["token"], json.dumps(status_payload))
        self.assertNotIn("private-debug-token", json.dumps(status_payload))

    @mock.patch.object(debug.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}")
    def test_task_reuse_fails_before_any_session_change(self, _which):
        self.info["run_dir"].mkdir(parents=True)
        with self.assertRaisesRegex(debug.DebugError, "already has a run directory") as caught:
            debug.start(self.info)
        self.assertEqual(caught.exception.code, "task_exists")
        self.assertEqual(self.commands, [])
        self.assertFalse(self.alive)

    @mock.patch.object(debug.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}")
    def test_existing_tmux_name_is_never_reused(self, _which):
        self.alive = True
        with self.assertRaisesRegex(debug.DebugError, "session name is already in use") as caught:
            debug.start(self.info)
        self.assertEqual(caught.exception.code, "task_exists")
        self.assertFalse(self.info["run_dir"].exists())
        self.assertFalse(any(command[:2] == ["tmux", "new-session"] for command in self.commands))

    @mock.patch.object(debug.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}")
    @mock.patch.object(debug, "port_free", side_effect=[True, False])
    @mock.patch.object(debug, "health_reachable")
    def test_port_conflict_starts_nothing(self, health, _ports, _which):
        with self.assertRaisesRegex(debug.DebugError, "port 3004 is occupied") as caught:
            debug.start(self.info)
        self.assertEqual(caught.exception.code, "port_in_use")
        self.assertEqual(caught.exception.details["port"], 3004)
        health.assert_not_called()
        self.assertFalse(self.info["run_dir"].exists())
        self.assertFalse(self.alive)

    @mock.patch.object(debug.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}")
    @mock.patch.object(debug, "port_free", return_value=True)
    @mock.patch.object(debug, "health_reachable", return_value=True)
    @mock.patch.object(debug, "cdp_has_page", return_value=False)
    @mock.patch.object(debug, "START_TIMEOUT", 0)
    def test_readiness_failure_preserves_private_artifacts_and_runner(self, *_mocks):
        with self.assertRaisesRegex(debug.DebugError, "artifacts preserved") as caught:
            debug.start(self.info)
        self.assertEqual(caught.exception.code, "startup_timeout")
        self.assertTrue(self.alive)
        self.assertTrue((self.info["run_dir"] / "owner.json").is_file())
        self.assertTrue((self.info["run_dir"] / "flutter.log").is_file())
        self.assertFalse(any(command[:3] == ["tmux", "kill-session", "-t"] for command in self.commands))

    def test_ownership_mismatch_blocks_reload_and_stop(self):
        self.make_owner()
        self.marker = "different-owner"
        for action in (lambda: debug.control(self.info, "r"), lambda: debug.stop(self.info)):
            with self.subTest(action=action), self.assertRaisesRegex(debug.DebugError, "ownership") as caught:
                action()
            self.assertEqual(caught.exception.code, "ownership_mismatch")
        self.assertFalse(any(command[:2] == ["tmux", "send-keys"] for command in self.commands))
        self.assertFalse(any("kill-session" in command for command in self.commands))

    def test_reload_targets_owned_pane_and_stop_quits_only_it(self):
        self.make_owner()
        reload_payload = debug.control(self.info, "r")
        self.assertIn(["tmux", "send-keys", "-t", self.info["pane"], "r"], self.commands)
        self.assertEqual((reload_payload["state"], reload_payload["completion"]), ("requested", "unchecked"))
        debug.control(self.info, "R")
        self.assertIn(["tmux", "send-keys", "-t", self.info["pane"], "R"], self.commands)
        self.pane_command = "make"
        with mock.patch.object(debug.shutil, "which", return_value=None), \
                mock.patch.object(debug, "port_free", return_value=True):
            stop_payload = debug.stop(self.info)
        self.assertEqual(stop_payload["state"], "stopped")
        self.assertEqual(stop_payload["browser_disconnect"], "manual")
        self.assertTrue(stop_payload["warnings"])
        self.assertIn("manually", stop_payload["next_action"])
        self.assertIn("new TASK slug", stop_payload["next_action"])
        self.assertNotIn(f"TASK={self.info['task']}", stop_payload["next_action"])
        self.assertIn(["tmux", "send-keys", "-t", self.info["pane"], "q", "C-m"], self.commands)
        self.assertFalse(any("kill-session" in command for command in self.commands))

    def test_browser_close_requires_exact_listed_session(self):
        owner = self.make_owner()
        executable = "/usr/bin/agent-browser"
        listing = subprocess.CompletedProcess(
            [], 0, json.dumps({"success": True, "data": {"sessions": [{"name": owner["browser"]}]}}), ""
        )
        original = self.fake_invoke

        def invoke_browser(args, timeout=5):
            if args[0] == "tmux":
                return original(args, timeout)
            self.commands.append(args)
            return listing

        with mock.patch.object(debug.shutil, "which", return_value=executable), \
                mock.patch.object(debug, "invoke", side_effect=invoke_browser):
            self.assertEqual(debug.disconnect_browser(owner), "closed")
        self.assertIn([executable, "--session", owner["browser"], "close"], self.commands)

        listing.stdout = json.dumps({"success": True, "data": {"unexpected": []}})
        self.commands.clear()
        with mock.patch.object(debug.shutil, "which", return_value=executable), \
                mock.patch.object(debug, "invoke", side_effect=invoke_browser):
            self.assertEqual(debug.disconnect_browser(owner), "manual")
        self.assertFalse(any(command[-1:] == ["close"] for command in self.commands))

    def test_stop_timeout_leaves_owned_session_and_never_kills_it(self):
        self.make_owner()
        original = self.fake_invoke

        def ignore_quit(args, timeout=5):
            if args[:2] == ["tmux", "send-keys"] and "q" in args:
                self.commands.append(args)
                return subprocess.CompletedProcess(args, 0, "", "")
            return original(args, timeout)

        with mock.patch.object(debug, "invoke", side_effect=ignore_quit), \
                mock.patch.object(debug.shutil, "which", return_value=None), \
                mock.patch.object(debug, "port_free", return_value=True), \
                mock.patch.object(debug, "STOP_TIMEOUT", 0):
            with self.assertRaisesRegex(debug.DebugError, "timed out") as caught:
                debug.stop(self.info)
        self.assertEqual(caught.exception.code, "stop_timeout")
        self.assertEqual(caught.exception.details["browser_disconnect"], "manual")
        self.assertTrue(caught.exception.details["warnings"])
        self.assertIn("manually", caught.exception.next_action)
        self.assertTrue(self.alive)
        self.assertTrue(any("q" in command for command in self.commands))
        self.assertFalse(any("kill-session" in command for command in self.commands))

    def test_stop_of_absent_session_is_idempotent_and_does_not_touch_browser(self):
        self.make_owner()
        self.alive = False
        with mock.patch.object(debug.shutil, "which") as which:
            payload = debug.stop(self.info)
        which.assert_not_called()
        self.assertEqual(payload["state"], "stopped")
        self.assertEqual(payload["browser_disconnect"], "absent")
        self.assertIn("new TASK slug", payload["next_action"])
        self.assertNotIn(f"TASK={self.info['task']}", payload["next_action"])
        self.assertEqual(self.commands, [["tmux", "has-session", "-t", self.info["session"]]])

    def test_status_rejects_owner_symlink(self):
        directory = self.info["run_dir"]
        directory.mkdir(parents=True, mode=0o700)
        directory.chmod(0o700)
        target = Path(self.temp.name) / "outside"
        target.write_text("{}", encoding="utf-8")
        (directory / "owner.json").symlink_to(target)
        with self.assertRaisesRegex(debug.DebugError, "private regular file") as caught:
            debug.status(self.info)
        self.assertEqual(caught.exception.code, "owner_invalid")
        (directory / "owner.json").unlink()
        (directory / "owner.json").write_text("not-json", encoding="utf-8")
        (directory / "owner.json").chmod(0o600)
        with self.assertRaisesRegex(debug.DebugError, "missing or corrupt"):
            debug.status(self.info)

    def test_status_without_artifacts_is_stopped_and_skips_cdp(self):
        with mock.patch.object(debug, "cdp_has_page") as cdp:
            payload = debug.status(self.info)
        self.assertEqual(payload["state"], "stopped")
        self.assertEqual(payload["readiness"]["cdp_page"], "not_checked")
        self.assertFalse(any(payload["artifacts"].values()))
        self.assertEqual(payload["next_action"], f"Run make debug-start TASK={self.info['task']} to start this task.")
        cdp.assert_not_called()
        self.assertEqual(self.commands, [])

    def test_status_does_not_probe_cdp_when_owned_runner_is_absent(self):
        self.make_owner()
        uri = self.info["run_dir"] / "vm-service.uri"
        uri.write_text("ws://stale-private-uri\n", encoding="utf-8")
        uri.chmod(0o600)
        self.alive = False
        with mock.patch.object(debug, "cdp_has_page", side_effect=AssertionError("must not probe foreign CDP")) as cdp:
            payload = debug.status(self.info)
        self.assertEqual(payload["state"], "stopped")
        self.assertEqual(payload["readiness"]["cdp_page"], "not_checked")
        self.assertEqual(payload["readiness"]["vm_service_uri_file"], "not_checked")
        self.assertTrue(payload["artifacts"]["vm_service_uri_file"])
        self.assertTrue(payload["artifacts"]["owner_metadata"])
        cdp.assert_not_called()

    def test_status_requires_owned_make_wrapper_and_skips_other_commands(self):
        self.make_owner()
        uri = self.info["run_dir"] / "vm-service.uri"
        uri.write_text("ws://stale-private-uri\n", encoding="utf-8")
        uri.chmod(0o600)
        with mock.patch.object(debug, "cdp_has_page", side_effect=AssertionError("must not probe foreign CDP")) as cdp:
            for command in ("flutter", "dart", "bash"):
                with self.subTest(command=command):
                    self.pane_command = command
                    payload = debug.status(self.info)
                    self.assertEqual(payload["state"], "stopped")
                    self.assertFalse(payload["readiness"]["owned_runner"])
                    self.assertEqual(payload["readiness"]["cdp_page"], "not_checked")
                    self.assertTrue(payload["artifacts"]["vm_service_uri_file"])
        cdp.assert_not_called()

    def test_status_runtime_readiness_is_separate_from_artifact_presence(self):
        self.make_owner()
        with mock.patch.object(debug, "cdp_has_page", return_value=True):
            payload = debug.status(self.info)
        self.assertEqual(payload["state"], "starting")
        self.assertFalse(payload["readiness"]["vm_service_uri_file"])
        self.assertFalse(payload["artifacts"]["vm_service_uri_file"])

        uri = self.info["run_dir"] / "vm-service.uri"
        uri.write_text("ws://private-debug-token\n", encoding="utf-8")
        uri.chmod(0o600)
        with mock.patch.object(debug, "cdp_has_page", return_value=False):
            payload = debug.status(self.info)
        self.assertEqual(payload["state"], "starting")
        self.assertTrue(payload["readiness"]["vm_service_uri_file"])
        self.assertFalse(payload["readiness"]["cdp_page"])
        self.assertTrue(payload["artifacts"]["vm_service_uri_file"])
        self.assertNotIn("private-debug-token", json.dumps(payload))

    def test_control_requires_make_wrapper_and_running_owner(self):
        self.make_owner()
        for command in ("flutter", "dart", "bash"):
            self.pane_command = command
            for key in ("r", "R"):
                with self.subTest(command=command, key=key), self.assertRaises(debug.DebugError) as caught:
                    debug.control(self.info, key)
                self.assertEqual(caught.exception.code, "operation_failed")
        self.assertFalse(any(command[:2] == ["tmux", "send-keys"] for command in self.commands))

        self.pane_command = "make"
        self.alive = False
        with self.assertRaises(debug.DebugError) as caught:
            debug.control(self.info, "r")
        self.assertEqual(caught.exception.code, "not_running")
        self.assertIn("new TASK slug", caught.exception.next_action)
        self.assertNotIn(f"TASK={self.info['task']}", caught.exception.next_action)

    def test_stop_requires_make_wrapper_before_sending_quit(self):
        self.make_owner()
        for command in ("flutter", "dart", "bash"):
            with self.subTest(command=command):
                self.pane_command = command
                with self.assertRaises(debug.DebugError) as caught:
                    debug.stop(self.info)
                self.assertEqual(caught.exception.code, "operation_failed")
                self.assertIn("make-launched Flutter runner", str(caught.exception))
        self.assertFalse(any(command[:2] == ["tmux", "send-keys"] for command in self.commands))

    def test_status_for_stopped_existing_task_recommends_a_new_slug(self):
        self.make_owner()
        self.alive = False
        payload = debug.status(self.info)
        self.assertEqual(payload["state"], "stopped")
        self.assertIn("new TASK slug", payload["next_action"])
        self.assertNotIn(f"TASK={self.info['task']}", payload["next_action"])

    def test_cli_emits_one_json_object_and_missing_task_error_is_actionable(self):
        self.root = Path(self.temp.name) / "repo 'quoted' $literal"
        self.root.mkdir()
        debug.ROOT = self.root
        self.info = debug.task_info("shape-resize")
        owner = self.make_owner()
        owner["token"] = "b" * 64
        owner_path = self.info["run_dir"] / "owner.json"
        owner_path.write_text(json.dumps(owner) + "\n", encoding="utf-8")
        owner_path.chmod(0o600)
        self.marker = owner["token"]
        uri = self.info["run_dir"] / "vm-service.uri"
        uri.write_text("ws://private-debug-token\n", encoding="utf-8")
        uri.chmod(0o600)
        with mock.patch.dict(os.environ, {"TASK": "shape-resize"}), \
                mock.patch.object(debug, "cdp_has_page", return_value=True), \
                contextlib.redirect_stdout(io.StringIO()) as stdout, \
                contextlib.redirect_stderr(io.StringIO()) as stderr:
            code = debug.main(["status"])
        self.assertEqual(code, 0)
        self.assertEqual(len(stdout.getvalue().splitlines()), 1)
        self.assertEqual(stderr.getvalue(), "")
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["state"], "ready")
        self.assertEqual(payload["action"], "status")
        self.assertEqual(payload["run_dir"], str(self.info["run_dir"]))
        self.assertIn("quoted", payload["log_path"])
        self.assertEqual(payload["cdp_url"], "http://127.0.0.1:3004")
        self.assertEqual(payload["ui_readiness"], "unchecked")
        self.assertEqual(payload["auth"], "not_managed")
        self.assertNotIn(owner["token"], stdout.getvalue())
        self.assertNotIn("private-debug-token", stdout.getvalue())

        with mock.patch.dict(os.environ, {}, clear=True), \
                contextlib.redirect_stdout(io.StringIO()) as stdout, \
                contextlib.redirect_stderr(io.StringIO()) as stderr:
            code = debug.main(["status"])
        self.assertEqual(code, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(len(stderr.getvalue().splitlines()), 1)
        failure = json.loads(stderr.getvalue())
        self.assertEqual(failure["error_code"], "missing_task")
        self.assertTrue(failure["message"])
        self.assertTrue(failure["next_action"])

        with mock.patch.dict(os.environ, {"TASK": "invalid/task"}, clear=True), \
                contextlib.redirect_stdout(io.StringIO()) as stdout, \
                contextlib.redirect_stderr(io.StringIO()) as stderr:
            code = debug.main(["status"])
        self.assertEqual(code, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(json.loads(stderr.getvalue())["error_code"], "invalid_task")

    @mock.patch.object(debug.shutil, "which", return_value=None)
    def test_missing_tool_is_categorized_before_starting(self, _which):
        with self.assertRaises(debug.DebugError) as caught:
            debug.start(self.info)
        self.assertEqual(caught.exception.code, "missing_tool")
        self.assertEqual(caught.exception.details["tool"], "python3")
        self.assertFalse(self.info["run_dir"].exists())

    @mock.patch.object(debug.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}")
    @mock.patch.object(debug, "port_free", return_value=True)
    @mock.patch.object(debug, "health_reachable", return_value=False)
    @mock.patch.object(debug, "CHROMIUM", mock.Mock(is_file=mock.Mock(return_value=True)))
    @mock.patch("debug.os.access", return_value=True)
    def test_unavailable_services_are_categorized(self, *_mocks):
        with self.assertRaises(debug.DebugError) as caught:
            debug.start(self.info)
        self.assertEqual(caught.exception.code, "services_unavailable")
        self.assertFalse(self.info["run_dir"].exists())


if __name__ == "__main__":
    unittest.main()
