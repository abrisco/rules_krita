"""Krita bzlmod extensions"""

load(
    "//krita/private:toolchain_repo.bzl",
    "CONSTRAINTS",
    "KRITA_DEFAULT_VERSION",
    "KRITA_STRIP_PREFIX",
    "KRITA_VERSIONS",
    "format_toolchain_value",
    "krita_toolchain_repository_hub",
    "krita_tools_repository",
)

def _find_modules(module_ctx):
    root = None
    for mod in module_ctx.modules:
        if mod.is_root:
            return mod

    return root

def _krita_impl(module_ctx):
    root = _find_modules(module_ctx)
    reproducible = True

    for attrs in root.tags.toolchain:
        if attrs.version not in KRITA_VERSIONS:
            fail("Krita toolchain hub `{}` was given unsupported version `{}`. Try: {}".format(
                attrs.name,
                attrs.version,
                KRITA_VERSIONS.keys(),
            ))
        available = KRITA_VERSIONS[attrs.version]
        toolchain_names = []
        toolchain_labels = {}
        exec_compatible_with = {}
        for platform, archive_info in available.items():
            tool_name = krita_tools_repository(
                name = "{}__{}".format(attrs.name, platform),
                version = attrs.version,
                platform = platform,
                integrity = archive_info["integrity"],
                strip_prefix = format_toolchain_value(
                    value = KRITA_STRIP_PREFIX[platform],
                    version = attrs.version,
                    platform = platform,
                    artifact = archive_info["artifact"],
                ),
                urls = [
                    format_toolchain_value(
                        value = url,
                        version = attrs.version,
                        platform = platform,
                        artifact = archive_info["artifact"],
                    )
                    for url in attrs.urls
                ],
            )

            toolchain_names.append(tool_name)
            toolchain_labels[tool_name] = "@{}".format(tool_name)
            exec_compatible_with[tool_name] = CONSTRAINTS[platform]

        krita_toolchain_repository_hub(
            name = attrs.name,
            toolchain_labels = toolchain_labels,
            toolchain_names = toolchain_names,
            exec_compatible_with = exec_compatible_with,
            target_compatible_with = {},
            target_settings = {},
        )

    return module_ctx.extension_metadata(
        reproducible = reproducible,
    )

_TOOLCHAIN_TAG = tag_class(
    doc = "An extension for defining a `krita_toolchain` from a download archive.",
    attrs = {
        "name": attr.string(
            doc = "The name of the toolchain.",
            mandatory = True,
        ),
        "urls": attr.string_list(
            doc = "Url templates to use for downloading Krita.",
            default = [
                "https://download.kde.org/Attic/krita/{semver}/{artifact}",
            ],
        ),
        "version": attr.string(
            doc = "The version of Krita to download.",
            default = KRITA_DEFAULT_VERSION,
        ),
    },
)

krita = module_extension(
    doc = "Bzlmod extensions for Krita",
    implementation = _krita_impl,
    tag_classes = {
        "toolchain": _TOOLCHAIN_TAG,
    },
)
