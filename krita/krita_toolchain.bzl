"""krita_toolchain"""

load(
    "//krita/private:toolchain.bzl",
    _current_krita_py_library = "current_krita_py_library",
    _krita_toolchain = "krita_toolchain",
)

krita_toolchain = _krita_toolchain
current_krita_py_library = _current_krita_py_library
