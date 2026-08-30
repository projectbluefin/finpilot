# Unit tests

BATS unit tests for the shell scripts in `build/`.

## Running

```bash
just test-unit      # or: bats tests/unit
```

Requires [bats-core](https://bats-core.readthedocs.io) (`sudo dnf install bats`
or `sudo apt-get install bats`). No CI workflow runs this suite yet — see the
tracking issue for `unit-tests.yml`.

## Conventions

- One `.bats` file per script under test, named after the script.
- `helpers/stub.bash` provides the sandbox and stub helpers:
  - `setup_sandbox` — per-test `SANDBOX` fake filesystem root, `STUB_BIN` on
    `PATH`, and `STUB_LOG` for recorded invocations.
  - `stub_command <name> [exit_code]` — fake executable that logs its argv.
  - `stub_log_contains <substring>` — assert a command was invoked.
- Scripts must never touch the real host filesystem. `clean-stage.sh` is driven
  through its `CLEAN_ROOT` prefix; commands with side effects (`dnf5`,
  `systemctl`, `mountpoint`) are stubbed.

## Coverage

| Script                  | Tests                       |
| ----------------------- | --------------------------- |
| `build/clean-stage.sh`  | `clean-stage.bats`          |
| `build/copr-helpers.sh` | `copr-helpers.bats`         |
| `build/00-image-info.sh`| none — see issue #287       |
| `build/10-build.sh`     | none — see issue #287       |

`00-image-info.sh` and `10-build.sh` write to hard-coded absolute paths
(`/usr/share/ublue-os`, `/usr/lib/os-release`, `/ctx/...`) and cannot be
sandboxed until they gain a root-prefix hook like `CLEAN_ROOT`.
