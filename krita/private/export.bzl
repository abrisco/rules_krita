"""krita_export"""

load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _krita_export_impl(ctx):
    krita_toolchain = ctx.toolchains[TOOLCHAIN_TYPE]

    output = ctx.outputs.out
    outputs = [output]
    inputs = [ctx.file.kra_file] + ctx.files.data

    args = ctx.actions.args()
    args.add("--krita", krita_toolchain.krita)
    args.add("--kra_file", ctx.file.kra_file)
    args.add("--output", ctx.outputs.out)

    ctx.actions.run(
        mnemonic = "KritaExport",
        executable = ctx.executable._process_wrapper,
        arguments = [args],
        outputs = outputs,
        inputs = depset(inputs),
        tools = krita_toolchain.all_files,
        env = ctx.configuration.default_shell_env,
    )

    return [
        DefaultInfo(
            files = depset(outputs),
            runfiles = ctx.runfiles(files = outputs),
        ),
    ]

# Some references: https://docs.krita.org/en/reference_manual/linux_command_line.html
krita_export = rule(
    doc = """\
A Bazel rule for exporting images from a `.kra` file.
""",
    implementation = _krita_export_impl,
    attrs = {
        "args": attr.string_dict(
            doc = "Any additional arguments to provide tot he export script",
        ),
        "data": attr.label_list(
            doc = "Additional files associated with the `.kra` file.",
            allow_files = True,
        ),
        "kra_file": attr.label(
            doc = "The `.kra` file to export from.",
            allow_single_file = [".kra"],
            mandatory = True,
        ),
        "out": attr.output(
            doc = "The file to export.",
        ),
        "_process_wrapper": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//krita/private:export_process_wrapper"),
        ),
    },
    toolchains = [
        TOOLCHAIN_TYPE,
    ],
)
