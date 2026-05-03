#!/usr/bin/env python3
"""
Patch Vapor's Package.swift so the VaporTesting target depends on the swift-testing package.

Vapor's Sources/VaporTesting imports Swift's `Testing` module but (as of Vapor 4.121.x) does not
declare a swift-testing package dependency. On Linux OSS toolchains that can leave the compiler
using an incomplete module map (missing `_TestingInternals`). Declaring the same dependency SwiftPM
uses for AppTests fixes the link/compile of VaporTesting.

Upstream: https://github.com/vapor/vapor/issues/3391 — remove this script once Vapor adds the
dependency in their manifest.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def main() -> int:
    pkg = Path(".build/checkouts/vapor/Package.swift")
    if not pkg.is_file():
        print(f"error: missing Vapor checkout at {pkg} (run `swift package resolve` first)", file=sys.stderr)
        return 1

    text = pkg.read_text(encoding="utf-8")
    if "github.com/apple/swift-testing.git" in text:
        print("Vapor Package.swift already references swift-testing; skipping patch.")
        return 0

    dep_marker = '.package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0")'
    if dep_marker not in text:
        print(
            "error: unexpected Vapor Package.swift layout (could not find swift-asn1 dependency line)",
            file=sys.stderr,
        )
        return 1
    text = text.replace(
        dep_marker,
        dep_marker + ',\n        .package(url: "https://github.com/apple/swift-testing.git", from: "6.2.0")',
        1,
    )

    target_marker = """        .target(
            name: "VaporTesting",
            dependencies: [
                .target(name: "VaporTestUtils"),
                .target(name: "Vapor"),
            ],
            swiftSettings: swiftSettings
        ),"""
    if target_marker not in text:
        print("error: unexpected Vapor Package.swift layout (VaporTesting target)", file=sys.stderr)
        return 1
    text = text.replace(
        target_marker,
        """        .target(
            name: "VaporTesting",
            dependencies: [
                .product(name: "Testing", package: "swift-testing"),
                .target(name: "VaporTestUtils"),
                .target(name: "Vapor"),
            ],
            swiftSettings: swiftSettings
        ),""",
        1,
    )

    try:
        os.chmod(pkg, 0o644)
    except OSError:
        pass
    pkg.write_text(text, encoding="utf-8")
    print("Patched .build/checkouts/vapor/Package.swift: VaporTesting now depends on swift-testing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
