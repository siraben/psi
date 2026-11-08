"""Shared subprocess isolation and capability vocabulary for the test suite."""

from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAPABILITIES = frozenset({"ansi", "color", "tui", "mcp", "repl-editline"})


def smoke_env(tmp: Path) -> dict[str, str]:
    homes = {name: tmp / name for name in ("home", "config", "state", "cache")}
    for path in homes.values():
        path.mkdir(parents=True, exist_ok=True)
    inherited = (
        "PATH", "USER", "LOGNAME", "LANG", "LC_ALL", "TZ", "TERM", "TMPDIR",
        "SSL_CERT_FILE", "NIX_SSL_CERT_FILE", "SSH_AUTH_SOCK",
        "ANTHROPIC_API_KEY", "PSI_ANTHROPIC_MODEL",
    )
    env = {key: os.environ[key] for key in inherited if os.environ.get(key)}
    env.setdefault("PATH", os.defpath)
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("LANG", "C.UTF-8")
    env.setdefault("LC_ALL", "C.UTF-8")
    env.update({
        "HOME": str(homes["home"]),
        "XDG_CONFIG_HOME": str(homes["config"]),
        "XDG_STATE_HOME": str(homes["state"]),
        "XDG_CACHE_HOME": str(homes["cache"]),
        "PWD": str(ROOT),
        # Fixtures opt into project resources; trust tests explicitly override.
        "PSI_TRUST": "always",
    })
    return env


def matches_name(name: str, name_filter: str | None, excludes: list[str]) -> bool:
    return (not name_filter or name_filter in name) and not any(ex in name for ex in excludes)


def apply_env(env: dict[str, str], overrides: dict[str, object]) -> dict[str, str]:
    result = env.copy()
    for key, value in overrides.items():
        if value is None:
            result.pop(key, None)
        else:
            result[key] = str(value)
    return result
