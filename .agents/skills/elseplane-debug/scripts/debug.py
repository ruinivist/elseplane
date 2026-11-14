"""Own one private Flutter debug run per explicit task."""

import hashlib
import json
import os
import re
import secrets
import shlex
import shutil
import socket
import stat
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
CHROMIUM = Path("/usr/bin/chromium")
PORTS = (3000, 3004)
START_TIMEOUT = 120
STOP_TIMEOUT = 30
TASK_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,47}\Z")
OWNER_KEYS = {"root", "task", "run_dir", "session", "pane", "browser", "token"}


class DebugError(Exception):
    def __init__(self, message, code="operation_failed", next_action=None, **details):
        super().__init__(message)
        self.code = code
        self.next_action = next_action
        self.details = details


def result(info, action, state, **fields):
    return {
        "task": info["task"] if info else None,
        "action": action,
        "state": state,
        "tmux_session": info["session"] if info else None,
        "browser_session": info["browser"] if info else None,
        "run_dir": str(info["run_dir"]) if info else None,
        "log_path": str(info["run_dir"] / "flutter.log") if info else None,
        "vm_service_uri_file": str(info["run_dir"] / "vm-service.uri") if info else None,
        "cdp_url": "http://127.0.0.1:3004",
        "ui_readiness": "unchecked",
        "auth": "not_restored" if action == "start" else "not_managed",
        **fields,
    }


def emit(payload, stream):
    print(json.dumps(payload, sort_keys=True), file=stream)


def artifact_present(path):
    return path.exists() or path.is_symlink()


def invoke(args, timeout=5):
    try:
        return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)
    except FileNotFoundError:
        tool = Path(args[0]).name
        raise DebugError(f"required local command is unavailable: {tool}", "missing_tool",
                         f"Install or restore {tool}, then retry.", tool=tool) from None
    except (OSError, subprocess.TimeoutExpired):
        raise DebugError("a required local command failed or timed out") from None


def task_info(task):
    if not task:
        raise DebugError("TASK is required; pass TASK=<lowercase-slug>", "missing_task",
                         "Run the command with TASK=<lowercase-slug>.")
    if not TASK_RE.fullmatch(task):
        raise DebugError("TASK must match [a-z0-9][a-z0-9-]{0,47}", "invalid_task",
                         "Use a lowercase slug with letters, digits, and hyphens only.")
    root_hash = hashlib.sha256(str(ROOT).encode()).hexdigest()[:8]
    return {
        "root": str(ROOT), "task": task,
        "run_dir": ROOT / "local-mediator" / "debug" / task,
        "session": f"elseplane-debug-{root_hash}-{task}",
        "pane": f"elseplane-debug-{root_hash}-{task}:0.0",
        "browser": f"elseplane-browser-{root_hash}-{task}",
    }


def port_free(port):
    with socket.socket() as sock:
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def open_local(url, timeout):
    return urllib.request.build_opener(urllib.request.ProxyHandler({})).open(url, timeout=timeout)


def health_reachable():
    try:
        with open_local("https://localhost:3003/health", timeout=3) as response:
            return 200 <= response.status < 300
    except Exception:
        return False


def cdp_has_page():
    try:
        with open_local("http://127.0.0.1:3004/json/list", timeout=2) as response:
            targets = json.load(response)
        return isinstance(targets, list) and any(
            isinstance(target, dict) and target.get("type") == "page" for target in targets
        )
    except Exception:
        return False


def regular_file(path, nonempty=False):
    try:
        info = path.lstat()
        return stat.S_ISREG(info.st_mode) and (not nonempty or info.st_size > 0)
    except OSError:
        return False


def create_private_file(path, content=None):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        if content is not None:
            stream.write(json.dumps(content, sort_keys=True) + "\n")


def load_owner(info):
    directory = info["run_dir"]
    try:
        dir_stat = directory.lstat()
        if not stat.S_ISDIR(dir_stat.st_mode) or stat.S_ISLNK(dir_stat.st_mode) or stat.S_IMODE(dir_stat.st_mode) != 0o700:
            raise DebugError("run directory is not a private owned directory", "owner_invalid",
                             "Do not change the artifacts manually; inspect the task directory.")
        path = directory / "owner.json"
        file_stat = path.lstat()
        if not stat.S_ISREG(file_stat.st_mode) or stat.S_ISLNK(file_stat.st_mode) or stat.S_IMODE(file_stat.st_mode) != 0o600:
            raise DebugError("owner metadata is not a private regular file", "owner_invalid",
                             "Do not change the artifacts manually; inspect the task directory.")
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(fd, encoding="utf-8") as stream:
            owner = json.load(stream)
    except (OSError, ValueError, UnicodeError):
        raise DebugError("owner metadata is missing or corrupt; refusing to act", "owner_invalid",
                         "Do not change the artifacts manually; inspect the task directory.") from None
    expected = {key: str(value) if isinstance(value, Path) else value for key, value in info.items()}
    if (not isinstance(owner, dict) or set(owner) != OWNER_KEYS
            or any(owner.get(key) != expected[key] for key in expected)
            or not isinstance(owner.get("token"), str)
            or not re.fullmatch(r"[0-9a-f]{64}", owner["token"])):
        raise DebugError("owner metadata does not match this task; refusing to act", "ownership_mismatch",
                         "Do not act on this run; inspect the task ownership metadata.")
    return owner


def session_present(session):
    return invoke(["tmux", "has-session", "-t", session]).returncode == 0


def owned_pane(owner):
    if not session_present(owner["session"]):
        return None
    marker = invoke(["tmux", "show-option", "-qv", "-t", owner["session"], "@elseplane-owner"])
    pane = invoke(["tmux", "display-message", "-p", "-t", owner["pane"], "-F",
                   "#{session_name} #{window_index} #{pane_index} #{pane_current_command}"])
    fields = pane.stdout.strip().split()
    if (marker.returncode or marker.stdout.rstrip("\n") != owner["token"]
            or pane.returncode or len(fields) < 4
            or fields[:3] != [owner["session"], "0", "0"]):
        raise DebugError("tmux ownership does not match this task; refusing to act", "ownership_mismatch",
                         "Do not act on this run; inspect the tmux ownership before retrying.")
    return fields[3]


def require_command(args, message):
    if invoke(args).returncode:
        raise DebugError(message)


def vm_uri_ready(info):
    return regular_file(info["run_dir"] / "vm-service.uri", nonempty=True)


def flutter_command(uri_path):
    flutter_args = shlex.join([
        "--web-run-headless", "--web-browser-debug-port=3004",
        "--web-browser-flag=--incognito", f"--vmservice-out-file={uri_path}",
    ]).replace("$", "$$")
    assignment = f"FLUTTER_RUN_ARGS={flutter_args}"
    command = shlex.join(["env", "CHROME_EXECUTABLE=/usr/bin/chromium", "make", "run", assignment])
    return "umask 077; exec " + command


def wait_ready(owner, info):
    deadline = time.monotonic() + START_TIMEOUT
    while True:
        if owned_pane(owner) is None:
            raise DebugError("owned Flutter session exited before readiness")
        if vm_uri_ready(info) and cdp_has_page():
            return
        if time.monotonic() >= deadline:
            raise DebugError("startup readiness timed out", "startup_timeout",
                             f"Run make debug-status TASK={info['task']} and inspect the private log before retrying.")
        time.sleep(1)


def start(info):
    for tool in ("python3", "tmux", "flutter", "make"):
        if shutil.which(tool) is None:
            raise DebugError(f"required tool is unavailable: {tool}", "missing_tool",
                             f"Install or restore {tool}, then retry.", tool=tool)
    if not CHROMIUM.is_file() or not os.access(CHROMIUM, os.X_OK):
        raise DebugError("required Chromium executable is unavailable at /usr/bin/chromium", "missing_tool",
                         "Install Chromium at /usr/bin/chromium, then retry.", tool="chromium")
    if info["run_dir"].exists() or info["run_dir"].is_symlink():
        raise DebugError("TASK already has a run directory; choose a new task slug", "task_exists",
                         "Choose a new TASK slug; existing artifacts were left untouched.")
    if session_present(info["session"]):
        raise DebugError("the deterministic tmux session name is already in use", "task_exists",
                         "Choose a different TASK slug; the existing tmux session was left untouched.")
    for port in PORTS:
        if not port_free(port):
            raise DebugError(f"required loopback port {port} is occupied; no process was changed", "port_in_use",
                             "Check which process owns the port; no process was changed.", port=port)
    if not health_reachable():
        raise DebugError("https://localhost:3003/health is not reachable", "services_unavailable",
                         "Start the local mediator services, then retry.")

    owner = {key: str(value) if isinstance(value, Path) else value for key, value in info.items()}
    owner["token"] = secrets.token_hex(32)
    old_umask = os.umask(0o077)
    try:
        info["run_dir"].parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        info["run_dir"].mkdir(mode=0o700)
        create_private_file(info["run_dir"] / "flutter.log")
        create_private_file(info["run_dir"] / "owner.json", owner)
    except OSError:
        raise DebugError(f"could not create private task artifacts at {info['run_dir']}", "operation_failed",
                         "Check local filesystem permissions and available space before retrying.") from None
    finally:
        os.umask(old_umask)

    try:
        require_command(["tmux", "new-session", "-d", "-s", info["session"], "-c", info["root"]],
                        "could not create the owned tmux session")
        require_command(["tmux", "set-option", "-t", info["session"], "@elseplane-owner", owner["token"]],
                        "could not mark the owned tmux session")
        require_command(["tmux", "set-option", "-w", "-t", f"{info['session']}:0", "remain-on-exit", "off"],
                        "could not configure the owned tmux window")
        if owned_pane(owner) is None:
            raise DebugError("owned tmux session disappeared before launch")
        log_command = "cat >> " + shlex.quote(str(info["run_dir"] / "flutter.log"))
        require_command(["tmux", "pipe-pane", "-o", "-t", info["pane"], log_command],
                        "could not attach the private Flutter log")
        if owned_pane(owner) is None:
            raise DebugError("owned tmux session disappeared before launch")
        require_command(["tmux", "send-keys", "-l", "-t", info["pane"],
                         flutter_command(info["run_dir"] / "vm-service.uri")],
                        "could not launch Flutter in the owned pane")
        if owned_pane(owner) is None:
            raise DebugError("owned tmux session disappeared before Flutter start")
        require_command(["tmux", "send-keys", "-t", info["pane"], "C-m"],
                        "could not start Flutter in the owned pane")
        wait_ready(owner, info)
    except DebugError as error:
        raise DebugError(f"{error}; artifacts preserved at {info['run_dir']}", error.code,
                         error.next_action, **error.details) from None
    return result(info, "start", "ready", readiness={
        "owned_runner": True, "vm_service_uri_file": True, "cdp_page": True,
    }, app_url="https://localhost:3002",
                  next_action=f"Use make debug-status TASK={info['task']} to check this run.")


def status(info):
    log = info["run_dir"] / "flutter.log"
    uri = info["run_dir"] / "vm-service.uri"
    if not artifact_present(info["run_dir"]):
        return result(info, "status", "stopped", readiness={
            "owned_runner": False, "vm_service_uri_file": "not_checked", "cdp_page": "not_checked",
        }, artifacts={"log": False, "vm_service_uri_file": False, "owner_metadata": False}, ports={
            str(port): "free" if port_free(port) else "occupied" for port in PORTS
        }, next_action=f"Run make debug-start TASK={info['task']} to start this task.")

    owner = load_owner(info)
    running = owned_pane(owner) == "make"
    uri_ready = vm_uri_ready(info) if running else None
    cdp_ready = cdp_has_page() if running else None
    state = "ready" if running and uri_ready and cdp_ready else "starting" if running else "stopped"
    return result(info, "status", state, readiness={
        "owned_runner": running,
        "vm_service_uri_file": uri_ready if running else "not_checked",
        "cdp_page": cdp_ready if running else "not_checked",
    }, artifacts={
        "log": artifact_present(log),
        "vm_service_uri_file": artifact_present(uri),
        "owner_metadata": artifact_present(info["run_dir"] / "owner.json"),
    }, ports={str(port): "free" if port_free(port) else "occupied" for port in PORTS},
                  next_action=(f"Use make debug-reload TASK={info['task']} or make debug-stop TASK={info['task']} to control this run."
                               if state == "ready" else
                               f"Run make debug-status TASK={info['task']} again after startup."
                                if state == "starting" else
                                "Choose a new TASK slug; this task's artifacts are preserved."))


def control(info, key):
    owner = load_owner(info)
    pane_command = owned_pane(owner)
    if pane_command is None:
        raise DebugError("owned tmux session is not running", "not_running",
                         "Choose a new TASK slug; this task's artifacts are preserved.")
    if pane_command != "make":
        raise DebugError("owned pane is not running the make-launched Flutter runner; refusing to send control key",
                         "operation_failed",
                         "Do not send a control key; verify the owned make-launched Flutter runner is active.")
    require_command(["tmux", "send-keys", "-t", owner["pane"], key],
                    "could not send control to the owned Flutter pane")
    action = "reload" if key == "r" else "restart"
    return result(info, action, "requested", completion="unchecked",
                  next_action=f"Run make debug-status TASK={info['task']} to check the run after the request.")


def browser_session_list(executable):
    try:
        result = invoke([executable, "session", "list", "--json"], timeout=10)
    except DebugError:
        return None
    if result.returncode:
        return None
    try:
        payload = json.loads(result.stdout)
    except (ValueError, TypeError):
        return None
    if not isinstance(payload, dict) or payload.get("success") is not True:
        return None
    data = payload.get("data")
    if not isinstance(data, dict) or not isinstance(data.get("sessions"), list):
        return None
    names = []
    for item in data["sessions"]:
        if isinstance(item, str):
            names.append(item)
        elif isinstance(item, dict) and isinstance(item.get("name"), str):
            names.append(item["name"])
        else:
            return None
    return names


def disconnect_browser(owner):
    executable = shutil.which("agent-browser")
    if executable is None:
        return "manual"
    names = browser_session_list(executable)
    if names is None:
        return "manual"
    if owner["browser"] not in names:
        return "absent"
    if owned_pane(owner) is None:
        return "absent"
    try:
        result = invoke([executable, "--session", owner["browser"], "close"], timeout=10)
    except DebugError:
        return "manual"
    return "closed" if result.returncode == 0 else "manual"


def stop_result(info, browser):
    warnings = (["Could not verify or close the owned browser session; disconnect it manually if attached."]
                if browser == "manual" else [])
    next_action = ("Choose a new TASK slug; this task's artifacts are preserved."
                   if artifact_present(info["run_dir"])
                   else f"Run make debug-start TASK={info['task']} to start this task.")
    if browser == "manual":
        next_action = f"If attached, close browser session {info['browser']} manually. {next_action}"
    return result(info, "stop", "stopped", browser_disconnect=browser, warnings=warnings,
                  readiness={"owned_runner": False, "vm_service_uri_file": "not_checked",
                             "cdp_page": "not_checked"},
                  artifacts={"log": artifact_present(info["run_dir"] / "flutter.log"),
                             "vm_service_uri_file": artifact_present(info["run_dir"] / "vm-service.uri"),
                             "owner_metadata": artifact_present(info["run_dir"] / "owner.json")},
                  next_action=next_action)


def stop(info):
    if not artifact_present(info["run_dir"]):
        return stop_result(info, "absent")
    owner = load_owner(info)
    pane_command = owned_pane(owner)
    if pane_command is None:
        return stop_result(info, "absent")
    if pane_command != "make":
        raise DebugError("owned pane is not running the make-launched Flutter runner; refusing to send q",
                         "operation_failed",
                         "Do not send quit; verify the owned make-launched Flutter runner is active.")
    browser = disconnect_browser(owner)
    warnings = (["Could not verify or close the owned browser session; disconnect it manually if attached."]
                if browser == "manual" else [])
    try:
        pane_command = owned_pane(owner)
        if pane_command is None:
            return stop_result(info, browser)
        if pane_command != "make":
            raise DebugError("owned pane changed before quit; refusing to send q", "operation_failed",
                             "Do not send quit; verify the owned make-launched Flutter runner is active.")
        require_command(["tmux", "send-keys", "-t", owner["pane"], "q", "C-m"],
                        "could not ask the owned Flutter process to quit")
        deadline = time.monotonic() + STOP_TIMEOUT
        while True:
            if owned_pane(owner) is None and all(port_free(port) for port in PORTS):
                return stop_result(info, browser)
            if time.monotonic() >= deadline:
                raise DebugError(f"graceful stop timed out; session and artifacts were left intact at {info['run_dir']}",
                                 "stop_timeout",
                                 f"Run make debug-status TASK={info['task']}; do not force-kill the owned session.")
            time.sleep(0.5)
    except DebugError as error:
        next_action = error.next_action
        if browser == "manual":
            followup = next_action or f"run make debug-status TASK={info['task']}."
            next_action = f"If attached, close browser session {owner['browser']} manually; {followup}"
        raise DebugError(str(error), error.code, next_action, browser_disconnect=browser,
                         warnings=warnings, **error.details) from None


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    actions = {"start", "status", "reload", "restart", "stop"}
    if len(argv) != 1 or argv[0] not in actions:
        action = argv[0] if len(argv) == 1 and argv[0] in actions else None
        failure = result(None, action, "error", error_code="invalid_action",
                         message="expected one of start, status, reload, restart, or stop",
                         next_action="Run debug.py with one supported action.")
        emit(failure, sys.stderr)
        return 2
    action = argv[0]
    info = None
    try:
        info = task_info(os.environ.get("TASK"))
        payload = {"start": start, "status": status, "reload": lambda i: control(i, "r"),
                   "restart": lambda i: control(i, "R"), "stop": stop}[action](info)
        emit(payload, sys.stdout)
        return 0
    except DebugError as error:
        next_action = error.next_action
        if next_action is None:
            next_action = (f"Run make debug-status TASK={info['task']} and inspect the private log before retrying."
                           if info else "Review TASK and rerun the command.")
        failure = result(info, action, "error", error_code=error.code, message=str(error),
                         next_action=next_action, **error.details)
        emit(failure, sys.stderr)
        return 1
    except Exception:
        failure = result(info, action, "error", error_code="operation_failed",
                         message="unexpected local debug operation failure; no cleanup was attempted",
                         next_action="Run make debug-status TASK=<task> and inspect the private artifacts.")
        emit(failure, sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
