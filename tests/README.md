# Tests

Build with `make -j4`, then run the offline suite:

```sh
python3 tests/smoke.py --psi build/psi --no-live
```

The compatibility CLI invokes pytest over this directory. `--filter TEXT` and
repeatable `--exclude TEXT` select by case name. Plain pytest works too:

```sh
python3 -m pytest tests --psi build/psi --no-live -q
```

## Ownership

- `lua/<category>/<case>.lua`: single-evaluation behavior tests.
- `smoke.py`: PTY, multi-process, CLI and opt-in live integration tests.
- `lua_runner.py`: declarative metadata, fixtures and output assertions.
- `test_support.py`: isolated subprocess environment and selection vocabulary.
- `conftest.py`: pytest collection, filters and compiled-capability skips.

Do not duplicate a declarative case in the legacy smoke registry. Test user
behavior, durable records or terminal-visible output rather than module paths,
current model-catalogue constants, or arbitrary physical wrap boundaries.

## Declarative cases

```lua
--[==[psi-test
expect = "42"
]==]
return 6 * 7
```

The level-2 Lua comment allows TOML array-of-table fixtures without closing the
comment accidentally. Case names default to relative paths without `.lua`.
Unknown metadata keys and cases without assertions are errors.

| Key | Meaning |
| --- | --- |
| `name` | Optional explicit case name |
| `expect` | Exact stdout after outer whitespace is stripped; empty is valid |
| `contains`, `not_contains` | String or list of nonempty stdout substrings |
| `regex` | Nonempty Python regular expression over stdout |
| `split` | `{sep = "\u007c", checks = [{index = 0, equals = "value"}]}`; checks can also use `contains` and `regex` |
| `cwd` | Fixture working directory relative to the test temp directory |
| `env` | String overrides; an empty value removes an inherited variable |
| `files` | Fixtures with `path` and one of `text`, `json`, or `mkdir = true` |
| `requires` | Compiled capabilities required by this test |
| `exit_only` | Explicitly permit a deliberate crash/boot test without output assertions |

Fixtures and environment values expand `{TMP}`, `{ROOT}`, and `{cwd}`. Test Lua
also receives `TMP` and `ROOT` locals. Environment isolation uses private HOME,
config, state and cache directories; only a small allowlist is inherited.
Project fixtures are trusted by default; trust tests override `PSI_TRUST`.

## Capability requirements

Capabilities are `tui`, `ansi`, `color`, `mcp`, and `repl-editline`. Declare them
on the test, not in CI exclusion substrings:

```toml
requires = ["tui", "color"]
```

Legacy smoke decorators accept `requires=("tui", "color")`; ordinary pytest
functions accept `@pytest.mark.requires("tui", "color")`. Collection queries the
selected binary's `runtime_info()` once in an isolated environment and skips
missing capabilities with an explicit reason. Collection-only discovery does not
need a binary. Pure Lua tests with mocked terminal output do not necessarily need
native TUI support. Tests for capability absence or fallback behavior should not
require the capability they are testing.

Live tests require `ANTHROPIC_API_KEY` and are disabled by `--no-live`. Keep
network/live coverage separate from deterministic local regression tests.
