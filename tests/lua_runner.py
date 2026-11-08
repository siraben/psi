"""Declarative Lua test runner for the psi smoke suite.

Each ``.lua`` file under ``tests/lua/`` is one test case. A TOML metadata
block at the top of the file describes the assertion shape, fixture
files, and environment overrides. The remainder of the file is the Lua
expression handed to ``psi --eval``.

Format::

    --[==[psi-test
    name = "eval/arithmetic"
    expect = "6"
    ]==]
    return 1 + 2 + 3

Metadata supports name, expect, contains, not_contains, regex, cwd, env, files,
split, requires (compiled capabilities), and exit_only (intentional crash checks).
"""

from __future__ import annotations

import json
import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from test_support import CAPABILITIES

LUA_DIR_NAME = "lua"
# Use a level-2 long-bracket comment ``--[==[psi-test ... ]==]`` so the
# embedded TOML can contain literal ``[[arr]]`` tables without prematurely
# closing the comment under real-Lua semantics (which level-0 ``--[[ ]]``
# would). chroma's Lua lexer follows the same rule, so the level-2 form
# also keeps Forgejo / GitHub syntax highlighting correct.
META_OPEN = "--[==[psi-test"
META_CLOSE = "]==]"


@dataclass
class FileSpec:
    path: str
    text: str | None = None
    json_value: Any | None = None
    mkdir: bool = False

    def render(self, base: Path, mapping: dict[str, str]) -> None:
        target = _resolve_path(self.path, base, mapping)
        if self.mkdir:
            target.mkdir(parents=True, exist_ok=True)
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        if self.json_value is not None:
            target.write_text(_render(json.dumps(self.json_value), mapping))
        else:
            target.write_text(_render(self.text or "", mapping))


@dataclass
class SplitCheck:
    sep: str
    checks: list[dict[str, Any]]


@dataclass
class LuaCase:
    file: Path
    name: str
    body: str
    expect: str | None = None
    contains: list[str] = field(default_factory=list)
    not_contains: list[str] = field(default_factory=list)
    regex: str | None = None
    cwd: str | None = None
    env: dict[str, str] = field(default_factory=dict)
    files: list[FileSpec] = field(default_factory=list)
    split: SplitCheck | None = None
    requires: list[str] = field(default_factory=list)
    exit_only: bool = False


def discover(root: Path) -> list[LuaCase]:
    """Find every ``.lua`` file under ``root/lua`` and parse it."""
    base = root / LUA_DIR_NAME
    if not base.exists():
        return []
    cases: list[LuaCase] = []
    for path in sorted(base.rglob("*.lua")):
        cases.append(parse_file(path, base))
    cases.sort(key=lambda c: c.name)
    return cases


def parse_file(path: Path, base: Path) -> LuaCase:
    text = path.read_text()
    meta_text, body = _split_meta(text)
    meta = tomllib.loads(meta_text) if meta_text else {}
    _validate_metadata(meta, path)

    default_name = path.relative_to(base).with_suffix("").as_posix()
    name = meta.get("name", default_name)

    contains = _as_list(meta.get("contains"))
    not_contains = _as_list(meta.get("not_contains"))

    files = []
    for spec in meta.get("files", []):
        files.append(FileSpec(
            path=spec["path"],
            text=spec.get("text"),
            json_value=spec.get("json"),
            mkdir=bool(spec.get("mkdir")),
        ))

    split = None
    if "split" in meta:
        s = meta["split"]
        split = SplitCheck(sep=s.get("sep", "|"), checks=s.get("checks", []))

    return LuaCase(
        file=path,
        name=name,
        body=body,
        expect=meta.get("expect"),
        contains=contains,
        not_contains=not_contains,
        regex=meta.get("regex"),
        cwd=meta.get("cwd"),
        env={k: str(v) for k, v in meta.get("env", {}).items()},
        files=files,
        split=split,
        requires=meta.get("requires", []),
        exit_only=meta.get("exit_only", False),
    )


def _validate_metadata(meta: dict[str, Any], path: Path) -> None:
    def reject(message: str) -> None:
        raise ValueError(f"{path}: {message}")

    allowed = {
        "name", "expect", "contains", "not_contains", "regex", "cwd", "env",
        "files", "split", "requires", "exit_only",
    }
    unknown = set(meta) - allowed
    if unknown:
        reject(f"unknown metadata keys: {', '.join(sorted(unknown))}")
    for key in ("name", "expect", "regex", "cwd"):
        if key in meta and not isinstance(meta[key], str):
            reject(f"{key} must be a string")
    for key in ("contains", "not_contains"):
        value = meta.get(key, [])
        if not isinstance(value, str) and not (
            isinstance(value, list) and all(isinstance(v, str) for v in value)
        ):
            reject(f"{key} must be a string or list of strings")
        if any(not v for v in _as_list(value)):
            reject(f"{key} must not contain empty assertions")
    requires = meta.get("requires", [])
    if not isinstance(requires, list) or any(
        not isinstance(v, str) or v not in CAPABILITIES for v in requires
    ):
        reject("requires must list known compiled capabilities")
    if not isinstance(meta.get("exit_only", False), bool):
        reject("exit_only must be a boolean")
    env = meta.get("env", {})
    if not isinstance(env, dict) or any(not isinstance(v, str) for v in env.values()):
        reject("env must map names to strings")
    files = meta.get("files", [])
    if not isinstance(files, list):
        reject("files must be a list")
    for spec in files:
        if not isinstance(spec, dict) or not isinstance(spec.get("path"), str):
            reject("each file needs a string path")
        if set(spec) - {"path", "text", "json", "mkdir"}:
            reject("unknown file fixture keys")
        if "text" in spec and not isinstance(spec["text"], str):
            reject("file text must be a string")
        if "mkdir" in spec and spec["mkdir"] is not True:
            reject("file mkdir must be true")
        if sum(key in spec for key in ("text", "json", "mkdir")) != 1:
            reject("file fixture must choose exactly one of text, json, or mkdir=true")
    split = meta.get("split")
    if split is not None:
        if not isinstance(split, dict) or set(split) - {"sep", "checks"}:
            reject("split must contain only sep and checks")
        if not isinstance(split.get("sep", "|"), str) or not split.get("sep", "|"):
            reject("split separator must be a nonempty string")
        checks = split.get("checks")
        if not isinstance(checks, list) or not checks:
            reject("split requires nonempty checks")
        for check in checks:
            if not isinstance(check, dict) or set(check) - {"index", "equals", "contains", "regex"}:
                reject("unknown split check keys")
            index = check.get("index")
            if type(index) is not int or index < 0:
                reject("split check index must be a nonnegative integer")
            predicates = set(check) - {"index"}
            if not predicates or any(not isinstance(check[k], str) for k in predicates):
                reject("split check needs string assertions")
            if any(check.get(k) == "" for k in ("contains", "regex")):
                reject("split check assertions must not be empty")
            if "regex" in check:
                re.compile(check["regex"])
    if "regex" in meta:
        if not meta["regex"]:
            reject("regex must not be empty")
        re.compile(meta["regex"])
    asserted = (
        "expect" in meta or bool(meta.get("contains")) or bool(meta.get("not_contains"))
        or "regex" in meta or split is not None
    )
    if not asserted and not meta.get("exit_only"):
        reject("case needs an output assertion or explicit exit_only=true")
    if asserted and meta.get("exit_only"):
        reject("exit_only cannot be combined with output assertions")


def prepare(case: LuaCase, tmp: Path, repo_root: Path) -> tuple[Path, dict[str, str], str]:
    """Materialise fixtures, render placeholders, and return (cwd, env, lua_body).

    The returned ``lua_body`` has a small prelude that exposes ``TMP`` and
    ``ROOT`` as locals so test files can use them without templating.
    """
    mapping = {"TMP": str(tmp), "ROOT": str(repo_root)}
    if case.cwd:
        cwd_path = (tmp / case.cwd).resolve()
        cwd_path.mkdir(parents=True, exist_ok=True)
    else:
        cwd_path = repo_root
    mapping["cwd"] = str(cwd_path)

    base = cwd_path if case.cwd else tmp
    for spec in case.files:
        spec.render(base, mapping)

    env = {k: _render(v, mapping) for k, v in case.env.items()}

    prelude = (
        f"local TMP = {json.dumps(str(tmp))}\n"
        f"local ROOT = {json.dumps(str(repo_root))}\n"
    )
    return cwd_path, env, prelude + case.body


def assert_output(case: LuaCase, output: str) -> None:
    """Apply every configured assertion. Raises AssertionError on failure."""
    stripped = output.strip()
    if case.expect is not None and stripped != case.expect:
        raise AssertionError(
            f"[{case.name}] expected {case.expect!r}, got {stripped!r}"
        )
    for needle in case.contains:
        if needle not in output:
            raise AssertionError(
                f"[{case.name}] missing {needle!r}\n--- got ---\n{output}"
            )
    for needle in case.not_contains:
        if needle in output:
            raise AssertionError(
                f"[{case.name}] unexpectedly contains {needle!r}\n--- got ---\n{output}"
            )
    if case.regex is not None and not re.search(case.regex, output, re.MULTILINE):
        raise AssertionError(
            f"[{case.name}] does not match /{case.regex}/\n--- got ---\n{output}"
        )
    if case.split is not None:
        parts = stripped.split(case.split.sep)
        for check in case.split.checks:
            idx = check["index"]
            if idx >= len(parts):
                raise AssertionError(
                    f"[{case.name}] split index {idx} out of range "
                    f"(have {len(parts)} parts: {parts!r})"
                )
            part = parts[idx]
            if "equals" in check and part != check["equals"]:
                raise AssertionError(
                    f"[{case.name}] split[{idx}] expected {check['equals']!r}, "
                    f"got {part!r}"
                )
            if "contains" in check and check["contains"] not in part:
                raise AssertionError(
                    f"[{case.name}] split[{idx}] missing {check['contains']!r} "
                    f"in {part!r}"
                )
            if "regex" in check and not re.search(check["regex"], part):
                raise AssertionError(
                    f"[{case.name}] split[{idx}] does not match "
                    f"/{check['regex']}/ in {part!r}"
                )


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _split_meta(text: str) -> tuple[str, str]:
    if not text.startswith(META_OPEN):
        return "", text
    end = text.find(META_CLOSE, len(META_OPEN))
    if end < 0:
        raise ValueError(f"unterminated {META_OPEN} block")
    meta = text[len(META_OPEN):end]
    body = text[end + len(META_CLOSE):]
    return meta.strip("\n"), body.lstrip("\n")


def _as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    return list(value)


def _render(value: str, mapping: dict[str, str]) -> str:
    out = value
    for key, replacement in mapping.items():
        out = out.replace("{" + key + "}", replacement)
    return out


def _resolve_path(p: str, base: Path, mapping: dict[str, str]) -> Path:
    rendered = _render(p, mapping)
    candidate = Path(rendered)
    if candidate.is_absolute():
        return candidate
    return base / candidate
