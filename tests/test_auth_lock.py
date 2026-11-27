"""Exercise OAuth refresh serialization with independent Psi processes."""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

from test_support import smoke_env


REFRESH = r"""
local store = require('psi.auth_storage')
local ready, go = os.getenv('PSI_TEST_READY'), os.getenv('PSI_TEST_GO')
local stale = assert(store.get('test'))
assert(stale.access == 'expired')
assert(psi.file_write_secure(ready, ''))
for i = 1, 200 do
  if psi.file_exists(go) then break end
  psi.sleep_ms(25)
end
assert(psi.file_exists(go), 'test barrier timed out')
local entry, err = store.ensure_oauth('test', stale, function(value)
  return type(value) == 'table' and value.type == 'oauth'
end, function(current)
  assert(current.refresh == 'original')
  print('refreshing')
  psi.sleep_ms(200)
  return {type='oauth', access='updated', refresh='rotated', expires=(os.time()+3600)*1000}
end)
assert(entry, err)
return entry.access
"""


def test_oauth_refresh_runs_once_across_processes(tmp_path: Path, pytestconfig):
    binary = Path(pytestconfig.getoption("--psi")).resolve()
    auth = tmp_path / "auth.json"
    go = tmp_path / "go"
    ready = [tmp_path / "ready-0", tmp_path / "ready-1"]
    stale = {"type": "oauth", "access": "expired", "refresh": "original", "expires": 0}
    auth.write_text(json.dumps({"test": stale}))
    auth.chmod(0o600)
    env = smoke_env(tmp_path)
    env.update(PSI_AUTH_FILE=str(auth), PSI_TEST_GO=str(go))
    processes = []
    try:
        for marker in ready:
            processes.append(
                subprocess.Popen(
                    [str(binary), "--eval", REFRESH],
                    env={**env, "PSI_TEST_READY": str(marker)},
                    cwd=tmp_path,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
            )
        # Both processes must have seen the stale token before either refreshes.
        deadline = time.monotonic() + 4
        while not all(marker.exists() for marker in ready) and time.monotonic() < deadline:
            time.sleep(0.01)
        assert all(marker.exists() for marker in ready)
        go.touch()
        output = []
        for process in processes:
            out, err = process.communicate(timeout=10)
            assert process.returncode == 0, err
            assert out.rstrip().endswith("updated"), out
            output.append(out)
        assert sum(text.count("refreshing") for text in output) == 1
        assert json.loads(auth.read_text())["test"]["refresh"] == "rotated"
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)
