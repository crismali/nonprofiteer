# Contributing

Notes for anyone (human or agent) re-scaffolding this project or adding Ash to a fresh Phoenix project the same way.

## igniter `:validate_compile_env` failure on fresh scaffold

`mix igniter.new ... --install ash,...` and `mix igniter.install ash,...` can fail mid-pipeline with a `:validate_compile_env` error — e.g. `enable_expensive_runtime_checks` for `phoenix_live_view`, then `bulk_actions_default_to_errors?` for `ash`. This can happen twice in a row on a clean scaffold attempt.

**Cause**: a stale compile manifest from before igniter adds the relevant app-env config.

**Fix**: `rm -rf _build && mix compile`, then retry the igniter command.
