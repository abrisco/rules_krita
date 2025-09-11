"""Krita toolchain repositories"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//krita/private:versions.bzl", _KRITA_VERSIONS = "KRITA_VERSIONS")
load("//tools/http_appimage:http_appimage.bzl", "http_appimage")
load("//tools/http_dmg:http_dmg.bzl", "http_dmg")

KRITA_DEFAULT_VERSION = "5.2.6"

KRITA_VERSIONS = _KRITA_VERSIONS

KRITA_PATHS = {
    "linux_x86_64": "usr/bin/krita",
    "macos_aarch64": "krita.app/Contents/MacOS/krita",
    "macos_x86_64": "krita.app/Contents/MacOS/krita",
    "windows_x86_64": "bin/krita.exe",
}

KRITARUNNER_PATHS = {
    "linux_x86_64": "usr/bin/kritarunner",
    "macos_aarch64": "krita.app/Contents/MacOS/kritarunner",
    "macos_x86_64": "krita.app/Contents/MacOS/kritarunner",
    "windows_x86_64": "bin/kritarunner.exe",
}

KRITA_STRIP_PREFIX = {
    "linux_x86_64": "",
    "macos_aarch64": "",
    "macos_x86_64": "",
    "windows_x86_64": "krita-x64-{version}",
}

CONSTRAINTS = {
    "linux_x86_64": ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    "macos_aarch64": ["@platforms//os:macos", "@platforms//cpu:aarch64"],
    "macos_x86_64": ["@platforms//os:macos", "@platforms//cpu:x86_64"],
    "windows_aarch64": ["@platforms//os:windows", "@platforms//cpu:aarch64"],
    "windows_x86_64": ["@platforms//os:windows", "@platforms//cpu:x86_64"],
}

_KRITA_TOOLCHAIN_BUILD_FILE_CONTENT = """\
load("@rules_krita//krita:krita_toolchain.bzl", "krita_toolchain")
load("@rules_venv//python:py_library.bzl", "py_library")

DATA = glob(
    include = ["**"],
    exclude = [
        ".DirIcon",
        "*.bazel",
        "**/*:*",
        "BUILD",
        "krita.png",
        "Terms Of Use/**",
        "WORKSPACE",
    ],
)

filegroup(
    name = "krita_bin",
    srcs = ["{krita}"],
    data = DATA,
)

filegroup(
    name = "kritarunner_bin",
    srcs = ["{kritarunner}"],
    data = DATA,
)

py_library(
    name = "pykrita",
    srcs = glob(
        include = {py_srcs_globs},
    ),
    data = glob(
        include = {py_data_globs},
        exclude = {py_srcs_globs},
        allow_empty = True,
    ),
    imports = {py_imports},
)

krita_toolchain(
    name = "toolchain",
    krita = ":krita_bin",
    kritarunner = ":kritarunner_bin",
    pykrita = ":pykrita",
    visibility = ["//visibility:public"],
)

alias(
    name = "{name}",
    actual = ":toolchain",
    visibility = ["//visibility:public"],
)
"""

_PYKRITA_PLATFORM_IMPORT = {
    "linux_x86_64": "usr/lib/krita-python-libs",
    "macos_aarch64": "Krita.app/Contents/Resources",
    "macos_x86_64": "Krita.app/Contents/Resources",
    "windows_x86_64": "lib/krita-python-libs",
}

def format_toolchain_value(value, version, platform, artifact):
    major_minor, _, _ = version.rpartition(".")

    return (
        value.replace("{major_minor}", major_minor)
            .replace("{semver}", version)
            .replace("{version}", version)
            .replace("{platform}", platform)
            .replace("{artifact}", artifact)
    )

def krita_tools_repository(*, name, version, platform, urls, integrity, **kwargs):
    """Download a version of Krita and instantiate targets for itl

    Args:
        name (str): The name of the repository to create.
        platform (str): The target platform of the Krita executable.
        version (str): The version of Krita.
        urls (list): A list of urls for fetching krita.
        integrity (str): The integrity checksum of the krita binary.
        **kwargs (dict): Additional keyword arguments.

    Returns:
        str: Return `name` for convenience.
    """
    archive_rule = http_archive
    for url in urls:
        if url.endswith(".dmg"):
            archive_rule = http_dmg
            break
        if url.endswith(".appimage"):
            archive_rule = http_appimage
            break

    # While not a url, the formatting does the same desired replacements
    py_import = format_toolchain_value(
        value = _PYKRITA_PLATFORM_IMPORT[platform],
        version = version,
        platform = platform,
        artifact = "",
    )

    py_imports = [py_import]
    py_srcs_glob_template = "{}/krita/**/*.py"
    py_data_glob_template = "{}/krita/**/*.{}"
    if "macos" not in platform:
        py_srcs_glob_template = "{}/**/*.py"
        py_data_glob_template = "{}/**/{}"
    py_srcs_globs = [py_srcs_glob_template.format(py_import)]
    py_data_globs = [
        py_data_glob_template.format(py_import, ext)
        for ext in [
            ".directory",
            "*.action",
            "*.bundle",
            "*.csv",
            "*.dll",
            "*.desktop",
            "*.directory",
            "*.dtd",
            "*.ggr",
            "*.gpl",
            "*.html",
            "*.kgm",
            "*.kpp",
            "*.kra",
            "*.kse",
            "*.kwl",
            "*.kws",
            "*.myb",
            "*.pat",
            "*.png",
            "*.predefinedimage",
            "*.profile",
            "*.pyc",
            "*.pyd",
            "*.pyi",
            "*.schema",
            "*.shortcuts",
            "*.stylesheet",
            "*.svg",
            "*.tag",
            "*.txt",
            "*.ui",
            "README",
        ]
    ]

    archive_rule(
        name = name,
        urls = urls,
        integrity = integrity,
        build_file_content = _KRITA_TOOLCHAIN_BUILD_FILE_CONTENT.format(
            name = name,
            krita = KRITA_PATHS[platform],
            kritarunner = KRITARUNNER_PATHS[platform],
            py_imports = repr(py_imports),
            py_srcs_globs = repr(py_srcs_globs),
            py_data_globs = repr(py_data_globs),
        ),
        **kwargs
    )

    return name

_BUILD_FILE_FOR_TOOLCHAIN_HUB_TEMPLATE = """
toolchain(
    name = "{name}",
    exec_compatible_with = {exec_constraint_sets_serialized},
    target_compatible_with = {target_constraint_sets_serialized},
    target_settings = {target_settings_serialized},
    toolchain = "{toolchain}",
    toolchain_type = "@rules_krita//krita:toolchain_type",
    visibility = ["//visibility:public"],
)
"""

def _BUILD_for_toolchain_hub(
        toolchain_names,
        toolchain_labels,
        target_settings,
        target_compatible_with,
        exec_compatible_with):
    return "\n".join([_BUILD_FILE_FOR_TOOLCHAIN_HUB_TEMPLATE.format(
        name = toolchain_name,
        exec_constraint_sets_serialized = json.encode(exec_compatible_with[toolchain_name]),
        target_constraint_sets_serialized = json.encode(target_compatible_with.get(toolchain_name, [])),
        target_settings_serialized = json.encode(target_settings.get(toolchain_name)) if toolchain_name in target_settings else "None",
        toolchain = toolchain_labels[toolchain_name],
    ) for toolchain_name in toolchain_names])

def _krita_toolchain_repository_hub_impl(repository_ctx):
    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.name,
    ))

    repository_ctx.file("BUILD.bazel", _BUILD_for_toolchain_hub(
        toolchain_names = repository_ctx.attr.toolchain_names,
        toolchain_labels = repository_ctx.attr.toolchain_labels,
        target_settings = repository_ctx.attr.target_settings,
        target_compatible_with = repository_ctx.attr.target_compatible_with,
        exec_compatible_with = repository_ctx.attr.exec_compatible_with,
    ))

krita_toolchain_repository_hub = repository_rule(
    doc = (
        "Generates a toolchain-bearing repository that declares a set of other toolchains from other " +
        "repositories. This exists to allow registering a set of toolchains in one go with the `:all` target."
    ),
    attrs = {
        "exec_compatible_with": attr.string_list_dict(
            doc = "A list of constraints for the execution platform for this toolchain, keyed by toolchain name.",
            mandatory = True,
        ),
        "target_compatible_with": attr.string_list_dict(
            doc = "A list of constraints for the target platform for this toolchain, keyed by toolchain name.",
            mandatory = True,
        ),
        "target_settings": attr.string_list_dict(
            doc = "A list of config_settings that must be satisfied by the target configuration in order for this toolchain to be selected during toolchain resolution.",
            mandatory = True,
        ),
        "toolchain_labels": attr.string_dict(
            doc = "The name of the toolchain implementation target, keyed by toolchain name.",
            mandatory = True,
        ),
        "toolchain_names": attr.string_list(
            mandatory = True,
        ),
    },
    implementation = _krita_toolchain_repository_hub_impl,
)
