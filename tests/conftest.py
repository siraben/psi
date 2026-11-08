from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

import lua_runner
import pytest
from test_support import CAPABILITIES, ROOT, matches_name, smoke_env


def pytest_addoption(parser):
    group = parser.getgroup("psi smoke")
    group.addoption("--psi", default="build/psi", help="path to psi binary")
    group.addoption("--filter", default=None, help="only run tests whose name contains this substring")
    group.addoption("--exclude", action="append", default=[],
                    help="skip tests whose name contains this substring; may be repeated")
    group.addoption("--no-live", action="store_true",
                    help="skip live-agent smoke tests even if ANTHROPIC_API_KEY is set")


def pytest_configure(config):
    config.addinivalue_line("markers", "requires(*capabilities): required compiled psi capabilities")


def _runtime_capabilities(config):
    binary = Path(config.getoption("--psi")).resolve()
    with tempfile.TemporaryDirectory(prefix="psi-capabilities-") as tmp:
        try:
            result = subprocess.run(
                [str(binary), "--no-extensions", "--no-prompt-templates", "--no-context-files",
                 "--no-trust", "--eval", "return psi.json_encode(psi.runtime_info())"],
                env=smoke_env(Path(tmp)), cwd=ROOT, text=True, capture_output=True,
                timeout=15, check=True,
            )
            info = json.loads(result.stdout)
            if not isinstance(info, dict) or any(type(info.get(key)) is not bool for key in CAPABILITIES):
                raise ValueError("runtime_info lacks boolean compiled capabilities")
            return info
        except (OSError, subprocess.SubprocessError, ValueError) as exc:
            raise pytest.UsageError(f"cannot inspect psi capabilities at {binary}: {exc}") from exc


def _case_info(item):
    params = getattr(getattr(item, "callspec", None), "params", {})
    if "lua_case" in params:
        case = params["lua_case"]
        return case.name, set(case.requires)
    if "smoke_case" in params:
        name, _fn, meta = params["smoke_case"]
        return name, set(meta.get("requires", ()))
    callspec = getattr(item, "callspec", None)
    return callspec.id if callspec is not None else item.name, set()


def pytest_collection_modifyitems(config, items):
    name_filter = config.getoption("--filter")
    excludes = config.getoption("--exclude") or []
    pending = []
    for item in items:
        name, required = _case_info(item)
        if not matches_name(name, name_filter, excludes):
            item.add_marker(pytest.mark.skip(reason="filtered out by --filter/--exclude"))
            continue
        for marker in item.iter_markers("requires"):
            required.update(marker.args)
        unknown = required - CAPABILITIES
        if unknown:
            raise pytest.UsageError(f"{item.nodeid}: unknown capabilities {sorted(unknown)}")
        if required:
            pending.append((item, required))
    if pending and not config.getoption("collectonly"):
        available = _runtime_capabilities(config)
        for item, required in pending:
            missing = sorted(key for key in required if not available[key])
            if missing:
                item.add_marker(pytest.mark.skip(reason="psi compiled without: " + ", ".join(missing)))


def pytest_generate_tests(metafunc):
    if "lua_case" in metafunc.fixturenames:
        cases = lua_runner.discover(Path(__file__).resolve().parent)
        metafunc.parametrize("lua_case", cases, ids=[case.name for case in cases])
