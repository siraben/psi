"""Capability collection policy exercised in an isolated pytest invocation."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from test_support import CAPABILITIES, smoke_env


@pytest.fixture
def capability_suite(tmp_path):
    suite = tmp_path / "suite"
    suite.mkdir()
    for name in ("conftest.py", "lua_runner.py", "test_support.py"):
        shutil.copy(Path(__file__).with_name(name), suite)
    (suite / "test_requirements.py").write_text(
        'import pytest\n'
        '@pytest.mark.requires("tui")\n'
        'def test_native_host(): pass\n'
        '@pytest.mark.requires("color")\n'
        'def test_compiled_color(): pass\n'
        'def test_tui_pure_lua_name(): pass\n'
    )
    return suite


def run_pytest(suite, *args):
    env = smoke_env(suite / "env")
    env["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = "1"
    return subprocess.run(
        [sys.executable, "-m", "pytest", "-c", "/dev/null", "--confcutdir", str(suite),
         str(suite), "-q", *args],
        check=False, cwd=suite, env=env, capture_output=True, text=True, timeout=30,
    )


def test_collect_only_does_not_require_binary(capability_suite):
    result = run_pytest(capability_suite, "--collect-only", "--psi", "/missing/psi")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "3 tests collected" in result.stdout


def test_execution_rejects_missing_binary(capability_suite):
    result = run_pytest(capability_suite, "--psi", "/missing/psi")
    assert result.returncode != 0
    assert "cannot inspect psi capabilities" in result.stderr


def test_collect_only_still_validates_requirements(capability_suite):
    path = capability_suite / "test_requirements.py"
    path.write_text(path.read_text().replace('requires("tui")', 'requires("tuii")'))
    result = run_pytest(capability_suite, "--collect-only", "--psi", "/missing/psi")
    assert result.returncode != 0
    assert "unknown capabilities" in result.stderr


def test_capability_probe_once_and_no_name_based_skips(capability_suite):
    binary = capability_suite / "psi"
    calls = capability_suite / "probes"
    info = {name: False for name in CAPABILITIES}
    binary.write_text(
        f"#!{sys.executable}\n"
        "from pathlib import Path\n"
        f"with Path({str(calls)!r}).open('a') as f: f.write('probe\\n')\n"
        f"print({json.dumps(info)!r})\n"
    )
    binary.chmod(0o755)
    result = run_pytest(capability_suite, "--psi", str(binary), "-rs")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "1 passed, 2 skipped" in result.stdout
    assert "psi compiled without: tui" in result.stdout
    assert calls.read_text().splitlines() == ["probe"]


def test_smoke_cli_collects_pty_cases_with_external_binary(tmp_path):
    binary = tmp_path / "missing-psi"
    assert not binary.exists()
    env = smoke_env(tmp_path / "env")
    env["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = "1"
    result = subprocess.run(
        [sys.executable, str(Path(__file__).with_name("smoke.py")),
         "--psi", str(binary), "--collect-only"],
        env=env, capture_output=True, text=True, check=False, timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "test_smoke_case[mode/tui_default]" in result.stdout
    assert "test_lua_case[providers/shared_sse_parser]" in result.stdout


def test_execution_rejects_uninspectable_binary(capability_suite):
    binary = capability_suite / "psi"
    binary.write_text(f"#!{sys.executable}\nprint('not runtime_info JSON')\n")
    binary.chmod(0o755)
    result = run_pytest(capability_suite, "--psi", str(binary))
    assert result.returncode != 0
    assert "cannot inspect psi capabilities" in result.stderr
