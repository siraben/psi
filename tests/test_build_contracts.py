"""Build/CI contracts, exercised without target dependency packages or Nix."""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
DEPS = ("LUA", "CJSON", "CURL", "ZLIB", "EDIT", "ARGTABLE")


def executable(path, text):
    path.write_text(text.replace("#!/bin/bash", f"#!{shutil.which('bash')}"))
    path.chmod(0o755)
    return path


@pytest.fixture
def build_tree(tmp_path):
    shutil.copy(ROOT / "Makefile", tmp_path)
    for name, text in {
        "src/main.c": "int main(void) { return 0; }\n",
        "src/optional.c": "int optional(void) { return 1; }\n",
        "scripts/embed.c": '#include <stdio.h>\nint main(int n, char **v) {\n'
                           'int i; for(i=1;i<n;i++) printf("/* %s */\\n", v[i]);\n'
                           'puts("typedef int embed_dummy;"); return 0; }\n',
        "lua/boot.lua": "-- boot\n",
        "lua/psi/optional.lua": "-- optional\n",
        "README.md": "readme\n",
        "docs/optional.md": "optional\n",
        "ca.pem": "test certificate\n",
    }.items():
        path = tmp_path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return tmp_path


def make(tree, *args, env=None):
    overrides = [f"PSI_{kind}_{dep}=" for dep in DEPS
                 for kind in ("CFLAGS", "LIBS")]
    result = subprocess.run(
        ["make", "--no-print-directory", "-j2", f"CC={shutil.which('cc')}",
         "CFLAGS=-O2", "CPPFLAGS=", "LDFLAGS=", "HARDENING=0", "GIT_COMMIT=test",
         "CA_BUNDLE_FILE=", "CURL_SSL_BACKENDS=", "HOST_CFLAGS_ZLIB=",
         "HOST_LIBS_ZLIB=", "PSI_LIBS_PTHREAD=", *overrides, *args],
        check=False, cwd=tree, env=env, text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return result


def snapshot(tree):
    return {str(p.relative_to(tree)): p.stat().st_mtime_ns
            for p in (tree / "build").rglob("*") if p.is_file()}


def test_make_configuration_noop_and_flag_changes(build_tree):
    make(build_tree)
    before = snapshot(build_tree)
    make(build_tree)
    assert snapshot(build_tree) == before
    make(build_tree, "LDFLAGS=-s")
    linked = snapshot(build_tree)
    assert linked["build/psi"] != before["build/psi"]
    assert linked["build/src/main.o"] == before["build/src/main.o"]
    make(build_tree, "LDFLAGS=-s", "CPPFLAGS=-DTEST_QUOTE='\"quoted\"'")
    compiled = snapshot(build_tree)
    assert compiled["build/src/main.o"] != linked["build/src/main.o"]
    assert compiled["build/embed"] == linked["build/embed"]
    make(build_tree, "LDFLAGS=-s", "CPPFLAGS=-DTEST_QUOTE='\"quoted\"'")
    assert snapshot(build_tree) == compiled


@pytest.mark.parametrize("flag", ["CFLAGS=-O0", "STRICT_CFLAGS=-std=c99",
                                   "DEPFLAGS=", "LUA_BOOT_FILE=/test/boot.lua",
                                   "GIT_COMMIT=changed", "CA_BUNDLE_FILE=/test/ca.pem",
                                   "CC=cc", "TUI=0", "ANSI=0", "COLOR=0", "MCP=0", "REPL_EDITLINE=0"])
def test_make_compile_configuration_inputs(build_tree, flag):
    make(build_tree)
    before = snapshot(build_tree)
    make(build_tree, flag)
    assert snapshot(build_tree)["build/src/main.o"] != before["build/src/main.o"]


def test_make_host_configuration_and_removed_blob_inputs(build_tree):
    make(build_tree)
    before = snapshot(build_tree)
    make(build_tree, "HOST_CFLAGS_ZLIB=-DHOST_CHANGED=1")
    after = snapshot(build_tree)
    for name in ("build/embed", "build/embedded_lua.c", "build/embedded_docs.c"):
        assert after[name] != before[name]
    assert after["build/src/main.o"] == before["build/src/main.o"]
    (build_tree / "lua/psi/optional.lua").unlink()
    (build_tree / "docs/optional.md").unlink()
    make(build_tree, "HOST_CFLAGS_ZLIB=-DHOST_CHANGED=1")
    assert "optional.lua" not in (build_tree / "build/embedded_lua.c").read_text()
    assert "optional.md" not in (build_tree / "build/embedded_docs.c").read_text()


def test_make_removed_source_and_optional_ca(build_tree):
    make(build_tree, "EMBED_CA_FILE=ca.pem")
    with_ca = snapshot(build_tree)
    assert "build/embedded_ca.o" in with_ca
    make(build_tree, "EMBED_CA_FILE=ca.pem", "EMBED_CA_KEY=alternate")
    assert "alternate" in (build_tree / "build/embedded_ca.c").read_text()
    before = snapshot(build_tree)
    (build_tree / "src/optional.c").unlink()
    make(build_tree)
    after = snapshot(build_tree)
    assert after["build/psi"] != before["build/psi"]
    assert after["build/src/main.o"] != before["build/src/main.o"]
    make(build_tree, "EMBED_CA_FILE=ca.pem")
    restored = snapshot(build_tree)
    assert restored["build/psi"] != after["build/psi"]
    assert restored["build/src/main.o"] != after["build/src/main.o"]


def test_make_embed_ca_path_change_uses_older_input(build_tree):
    make(build_tree, "EMBED_CA_FILE=ca.pem")
    other = build_tree / "other.pem"
    other.write_text("alternate test certificate\n")
    os.utime(other, (1, 1))
    make(build_tree, "EMBED_CA_FILE=other.pem")
    assert "other.pem" in (build_tree / "build/embedded_ca.c").read_text()
    assert "ca.pem" not in (build_tree / "build/embedded_ca.c").read_text()


def test_make_removed_source_relinks_without_recompiling(build_tree):
    make(build_tree)
    before = snapshot(build_tree)
    (build_tree / "src/optional.c").unlink()
    make(build_tree)
    after = snapshot(build_tree)
    assert after["build/psi"] != before["build/psi"]
    assert after["build/src/main.o"] == before["build/src/main.o"]


@pytest.mark.parametrize("origin", ["environment", "command-line"])
def test_make_explicit_empty_overrides_bypass_pkg_config(tmp_path, origin):
    probe = executable(tmp_path / "pkg-config", '#!/bin/sh\necho called >> "$PROBE_LOG"\nexit 1\n')
    env = dict(os.environ, PROBE_LOG=str(tmp_path / "probes"))
    empty = {f"PSI_{kind}_{dep}": "" for dep in DEPS for kind in ("CFLAGS", "LIBS")}
    empty["PSI_LIBS_PTHREAD"] = ""
    args = ["make", "-n", "HARDENING=0", f"PKG_CONFIG={probe}",
            "HOST_CFLAGS_ZLIB=", "HOST_LIBS_ZLIB=", "BUILD_DIR=probe-build"]
    base_args = args.copy()
    if origin == "environment":
        env.update(empty)
    else:
        args.extend(f"{key}={value}" for key, value in empty.items())
    result = subprocess.run(args, cwd=ROOT, env=env, check=True, text=True, capture_output=True)
    assert not (tmp_path / "probes").exists()
    assert "-largtable3" not in result.stdout
    assert "-lpthread" not in result.stdout
    # Undefined overrides must still query pkg-config and use library fallbacks.
    for key in empty:
        env.pop(key, None)
    result = subprocess.run(base_args, cwd=ROOT, env=env, check=True, text=True, capture_output=True)
    assert (tmp_path / "probes").exists()
    assert "-largtable3" in result.stdout
    assert "-lpthread" in result.stdout


def test_make_analyzers_leave_normal_build_intact(build_tree):
    make(build_tree)
    before = snapshot(build_tree)
    # Only test build isolation here, not availability of GCC's analyzer.
    compiler = executable(build_tree / "analyzer-cc", '''#!/bin/bash
args=()
for arg in "$@"; do [ "$arg" = -fanalyzer ] || args+=("$arg"); done
exec cc "${args[@]}"
''')
    make(build_tree, "analyze-gcc", f"CC={compiler}")
    assert (build_tree / "build-analyze-gcc/psi").exists()
    scan = executable(build_tree / "scan", '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\nexec "$@"\n')
    make(build_tree, "analyze-scan-build", f"SCAN_BUILD={scan}", "SCAN_BUILD_CC=cc")
    assert (build_tree / "build-analyze-scan/psi").exists()
    assert snapshot(build_tree) == before


@pytest.fixture
def ci_tools(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
               CALL_LOG=str(tmp_path / "calls"), PACKAGE_OUT=str(tmp_path / "package"))
    executable(bin_dir / "nix", '''#!/bin/bash
if [ "$1" = build ]; then echo "$PACKAGE_OUT"; exit; fi
shift
[ "$1" = --command ] && shift
exec "$@"
''')
    executable(bin_dir / "make", '#!/bin/sh\nprintf "make %s\\n" "$*" >> "$CALL_LOG"\n')
    executable(bin_dir / "python3", '#!/bin/sh\nprintf "python %s\\n" "$*" >> "$CALL_LOG"\n')
    return tmp_path, env


def test_ci_build_smokes_requested_build_directory(ci_tools):
    path, env = ci_tools
    env["CI_BUILD_DIR"] = str(path / "non-default")
    subprocess.run(["bash", "scripts/ci/build-and-smoke.sh"], cwd=ROOT, env=env, check=True,
                   capture_output=True)
    calls = (path / "calls").read_text()
    assert f"make BUILD_DIR={env['CI_BUILD_DIR']}" in calls
    assert f"--psi {env['CI_BUILD_DIR']}/psi --no-live" in calls


@pytest.mark.parametrize("expect,exists,status", [("true", False, 1), ("false", False, 0),
                                                ("true", True, 0), ("invalid", False, 1)])
def test_ci_package_expected_executable_policy(ci_tools, expect, exists, status):
    path, env = ci_tools
    env.update(PACKAGE_ATTR="test-package", EXPECT_PSI=expect)
    if exists:
        (path / "package/bin").mkdir(parents=True)
        executable(path / "package/bin/psi", "#!/bin/sh\nexit 0\n")
    result = subprocess.run(["bash", "scripts/ci/package-smoke.sh"], check=False, cwd=ROOT, env=env,
                            capture_output=True)
    assert result.returncode == status
    assert (path / "calls").exists() == (expect == "true" and exists)


def test_build_configs_deduplicates_only_normalized_tui(tmp_path):
    tests = tmp_path / "tests"
    tests.mkdir()
    shutil.copy(ROOT / "tests/build_configs.sh", tests)
    maker = executable(tmp_path / "make", '''#!/bin/bash
root=$2; shift 2
for arg in "$@"; do export "$arg"; done
[ "$ANSI" = 0 ] && TUI=0
expected_tui=false; expected_ansi=false; expected_color=false
[ "$TUI" = 1 ] && expected_tui=true
[ "$ANSI" = 1 ] && expected_ansi=true
[ "$ANSI" = 1 ] && [ "$COLOR" = 1 ] && expected_color=true
mkdir -p "$root/$BUILD_DIR"
printf '#!/bin/sh\\necho "%s|%s|%s"\\n' "$expected_tui" "$expected_ansi" "$expected_color" > "$root/$BUILD_DIR/psi"
chmod +x "$root/$BUILD_DIR/psi"
echo "$TUI $ANSI $COLOR $REPL_EDITLINE" >> "$root/configs"
''')
    subprocess.run(["sh", str(tests / "build_configs.sh")],
                   env=dict(os.environ, MAKE=str(maker)), check=True, capture_output=True)
    configs = (tmp_path / "configs").read_text().splitlines()
    assert len(configs) == 13  # 12 unique builds and one normalization check.
    assert len(set(configs)) == 12
    assert configs[-1] == "0 0 1 1"
