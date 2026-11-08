"""Test harness contracts independently of a built psi binary."""

from pathlib import Path

import lua_runner
import pytest
from test_support import apply_env, matches_name, smoke_env


def parse(tmp_path: Path, metadata: str):
    path = tmp_path / "case.lua"
    path.write_text("--[==[psi-test\n" + metadata + "\n]==]\nreturn 42")
    return lua_runner.parse_file(path, tmp_path)


@pytest.mark.parametrize("metadata", [
    'exepct = "42"',
    'expect = 42',
    'contains = [42]',
    'contains = [""]',
    'regex = ""',
    'requires = ["tuii"]\nexpect = "42"',
    'requires = "tui"\nexpect = "42"',
    'env = { HOME = 42 }\nexpect = "42"',
    'files = [{path = 42}]\nexpect = "42"',
    'files = [{path = "x"}]\nexpect = "42"',
    'files = [{path = "x", mkdir = false}]\nexpect = "42"',
    'files = [{path = "x", text = "a", mkdir = true}]\nexpect = "42"',
    'split = {checks = []}',
    'split = {checks = [{index = -1, equals = "42"}]}',
    'split = {checks = [{index = true, equals = "42"}]}',
    'split = {checks = [{index = 0}]}',
    'split = {sep = "", checks = [{index = 0, equals = "42"}]}',
    'split = {checks = [{index = 0, contains = ""}]}',
    'exit_only = "true"',
    'exit_only = true\nexpect = "42"',
    '',
])
def test_metadata_rejects_silent_weakening(tmp_path, metadata):
    with pytest.raises(ValueError):
        parse(tmp_path, metadata)


def test_assertions_detect_wrong_output(tmp_path):
    case = parse(tmp_path, 'expect = "42"\nrequires = ["tui"]')
    lua_runner.assert_output(case, "42\n")
    with pytest.raises(AssertionError):
        lua_runner.assert_output(case, "43\n")
    assert case.requires == ["tui"]


def test_empty_expected_output_is_a_real_assertion(tmp_path):
    case = parse(tmp_path, 'expect = ""')
    lua_runner.assert_output(case, "")
    with pytest.raises(AssertionError):
        lua_runner.assert_output(case, "unexpected")


def test_explicit_exit_only(tmp_path):
    case = parse(tmp_path, 'exit_only = true')
    assert case.exit_only


def test_split_assertions_apply_to_selected_part(tmp_path):
    case = parse(tmp_path, 'split = {checks = [{index = 1, equals = "42"}]}')
    lua_runner.assert_output(case, "answer|42")
    for output in ("answer|43", "42"):
        with pytest.raises(AssertionError):
            lua_runner.assert_output(case, output)


@pytest.mark.parametrize("name_filter,excludes,expected", [
    (None, [], True), ("read", [], True), ("write", [], False),
    (None, ["read"], False), ("read", ["tool/"], False),
])
def test_name_selection_is_shared(name_filter, excludes, expected):
    assert matches_name("tool/read", name_filter, excludes) is expected


def test_env_isolates_credentials_and_preserves_allowed_settings(tmp_path, monkeypatch):
    monkeypatch.setenv("PSI_AUTH_FILE", "/private/auth.json")
    monkeypatch.setenv("PSI_EXTENSIONS_DIR", "/untrusted/extensions")
    monkeypatch.setenv("OPENAI_API_KEY", "not-a-real-key")
    monkeypatch.setenv("PATH", "/test/bin")
    monkeypatch.setenv("PSI_TRUST", "never")
    env = smoke_env(tmp_path)
    assert not {"PSI_AUTH_FILE", "PSI_EXTENSIONS_DIR", "OPENAI_API_KEY"} & env.keys()
    assert env["PATH"] == "/test/bin"
    assert env["PSI_TRUST"] == "always"
    for key, directory in (("HOME", "home"), ("XDG_CONFIG_HOME", "config"),
                           ("XDG_STATE_HOME", "state"), ("XDG_CACHE_HOME", "cache")):
        assert Path(env[key]) == tmp_path / directory
        assert Path(env[key]).is_dir()
    overridden = apply_env(env, {"HOME": None, "PSI_TRUST": "never", "EMPTY": ""})
    assert "HOME" not in overridden
    assert overridden["PSI_TRUST"] == "never"
    assert overridden["EMPTY"] == ""
    assert env["HOME"] == str(tmp_path / "home")
    assert env["PSI_TRUST"] == "always"
