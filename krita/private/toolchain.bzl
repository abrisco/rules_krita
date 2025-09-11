"""A toolchain for Krita"""

load("@rules_venv//python:py_info.bzl", "PyInfo")

TOOLCHAIN_TYPE = str(Label("//krita:toolchain_type"))

def _krita_toolchain_impl(ctx):
    all_files = []
    if DefaultInfo in ctx.attr.krita:
        all_files.extend([
            ctx.attr.krita[DefaultInfo].files,
            ctx.attr.krita[DefaultInfo].default_runfiles.files,
        ])

    if DefaultInfo in ctx.attr.kritarunner:
        all_files.extend([
            ctx.attr.kritarunner[DefaultInfo].files,
            ctx.attr.kritarunner[DefaultInfo].default_runfiles.files,
        ])

    all_files = depset(transitive = all_files)

    return [
        platform_common.ToolchainInfo(
            krita = ctx.executable.krita,
            kritarunner = ctx.executable.kritarunner,
            pykrita = ctx.attr.pykrita,
            all_files = all_files,
        ),
    ]

krita_toolchain = rule(
    doc = "Define a toolchain for Krita rules.",
    implementation = _krita_toolchain_impl,
    attrs = {
        "krita": attr.label(
            doc = "The path to a krita binary.",
            cfg = "exec",
            executable = True,
            allow_single_file = True,
            mandatory = True,
        ),
        "kritarunner": attr.label(
            doc = "The path to a kritarunner binary.",
            cfg = "exec",
            executable = True,
            allow_single_file = True,
            mandatory = True,
        ),
        "pykrita": attr.label(
            doc = "The label to a [Krita Python API](https://docs.krita.org/en/user_manual/python_scripting/introduction_to_python_scripting.html) target.",
            providers = [PyInfo],
            mandatory = True,
        ),
    },
)

def _current_krita_py_library_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]

    target = toolchain.pykrita

    return [
        DefaultInfo(
            files = target[DefaultInfo].files,
            runfiles = target[DefaultInfo].default_runfiles,
        ),
        target[PyInfo],
        target[InstrumentedFilesInfo],
    ]

current_krita_py_library = rule(
    doc = "A rule for exposing the [Krita Python API](https://docs.krita.org/api/current/index.html)",
    implementation = _current_krita_py_library_impl,
    toolchains = [TOOLCHAIN_TYPE],
    provides = [PyInfo],
)
