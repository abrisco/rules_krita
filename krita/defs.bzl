"""# rules_krita
"""

load(
    ":krita_export.bzl",
    _krita_export = "krita_export",
)
load(
    ":krita_toolchain.bzl",
    _krita_toolchain = "krita_toolchain",
)

krita_export = _krita_export
krita_toolchain = _krita_toolchain
