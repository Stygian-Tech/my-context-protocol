# CI helper scripts

## `patch-vapor-swift-testing.py`

Vapor’s `VaporTesting` module imports Swift’s `Testing` framework, but Vapor’s `Package.swift` does not yet list the `swift-testing` package as a dependency. On Linux, that can produce a broken module map (missing `_TestingInternals`).

After `swift package resolve`, run:

```bash
python3 scripts/patch-vapor-swift-testing.py
```

The script edits `.build/checkouts/vapor/Package.swift` idempotently.

**CI:** `.depot/workflows/ci.yml` embeds the same logic as a `python3 <<'PATCH_VAPOR_EOF'` heredoc so jobs do not depend on `scripts/` being present on the branch (commit the script anyway for local use and documentation).

When Vapor adds the dependency upstream, delete this script and remove the embedded + file-based patch from CI.
