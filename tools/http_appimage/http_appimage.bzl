"""http_appimage"""

load(
    "@bazel_tools//tools/build_defs/repo:utils.bzl",
    "get_auth",
)

def _move(repository_ctx, src, dst):
    if not hasattr(repository_ctx, "rename"):
        program = "mv"
        if "win" in repository_ctx.os.name:
            program = "move"
        result = repository_ctx.execute([program, src, dst])
        if result.return_code:
            fail("mv failed with {}\nstdout:\n{}\nstderr:\n{}".format(
                result.return_code,
                result.stdout,
                result.stderr,
            ))
        return

    repository_ctx.rename(src, dst)

def _extract_appimage(
        *,
        repository_ctx,
        appimage,
        output = None,
        strip_prefix = ""):
    """Extract an appimage to the repository directory.

    Args:
        repository_ctx (repository_ctx): The rule's repository context.
        appimage (path): The path to the `.appimage` file.
        output (str, optional): path to the directory where the archive will be unpacked, relative to the repository directory.
        strip_prefix (str, optional): a directory prefix to strip from the extracted files.
    """
    if "mac" in repository_ctx.os.name or "win" in repository_ctx.os.name:
        # buildifier: disable=print
        print("WARNING: extracting an appimage on a non-linux system may fail.")

    if not output:
        output = "."

    temp_out_dir = repository_ctx.path("squashfs-root")

    command = [appimage, "--appimage-extract"]
    result = repository_ctx.execute(command)
    if result.return_code != 0:
        fail("appimage command failed with exit code {}\n{}\n\nstdout:\n{}\nstderr:\n{}".format(
            result.return_code,
            " ".join([str(a) for a in command]),
            result.stdout,
            result.stderr,
        ))

    target_dir = temp_out_dir

    # Check to see if any prefixes can be stripped
    if strip_prefix:
        stripped_dir = target_dir.get_child(strip_prefix)
        if not stripped_dir.exists:
            fail("Prefix \"{}\" was given, but not found in the archive. Here are possible prefixes for this archive: {}".format(
                strip_prefix,
                [p.basename for p in target_dir.readdir()],
            ))
        target_dir = stripped_dir

    # Move the extracted contents to the root of the directory, leaving known bad files.
    for item in target_dir.readdir():
        _move(repository_ctx, item, repository_ctx.path("{}/{}".format(output, item.basename)))

    repository_ctx.delete(temp_out_dir)

def _http_appimage_impl(repository_ctx):
    if repository_ctx.attr.build_file and repository_ctx.attr.build_file_content:
        fail("Only one of build_file and build_file_content can be provided.")

    appimage = repository_ctx.path("archive.appimage")

    repository_ctx.report_progress("Downloading appimage.")
    download_results = repository_ctx.download(
        url = repository_ctx.attr.urls,
        output = appimage,
        integrity = repository_ctx.attr.integrity,
        sha256 = repository_ctx.attr.sha256,
        auth = get_auth(repository_ctx, repository_ctx.attr.urls),
        executable = True,
    )

    repository_ctx.report_progress("Extracting appimage.")
    _extract_appimage(
        repository_ctx = repository_ctx,
        appimage = appimage,
        strip_prefix = repository_ctx.attr.strip_prefix,
    )

    build_file_content = repository_ctx.attr.build_file_content
    if repository_ctx.attr.build_file:
        repository_ctx.read(repository_ctx.path(repository_ctx.attr.build_file))
    repository_ctx.file("BUILD.bazel", content = build_file_content)
    repository_ctx.file("WORKSPACE.bazel", content = """workspace(name = "{}")""".format(repository_ctx.name))

    # Delete appimage remnants
    repository_ctx.delete(appimage)

    # Return reproducibility attributes
    repro_attrs = {
        k: getattr(repository_ctx.attr, k)
        for k in _ATTRS.keys()
    }

    repro_attrs["name"] = repository_ctx.attr.name

    if not repository_ctx.attr.sha256:
        repro_attrs["integrity"] = download_results.integrity

    return repro_attrs

_ATTRS = {
    "auth_patterns": attr.string_dict(
        doc = """An optional dict mapping host names to custom authorization patterns.

If a URL's host name is present in this dict the value will be used as a pattern when
generating the authorization header for the http request. This enables the use of custom
authorization schemes used in a lot of common cloud storage providers.

The pattern currently supports 2 tokens: <code>&lt;login&gt;</code> and
<code>&lt;password&gt;</code>, which are replaced with their equivalent value
in the netrc file for the same host name. After formatting, the result is set
as the value for the <code>Authorization</code> field of the HTTP request.

Example attribute and netrc for a http download to an oauth2 enabled API using a bearer token:

<pre>
auth_patterns = {
    "storage.cloudprovider.com": "Bearer &lt;password&gt;"
}
</pre>

netrc:

<pre>
machine storage.cloudprovider.com
        password RANDOM-TOKEN
</pre>

The final HTTP request would have the following header:

<pre>
Authorization: Bearer RANDOM-TOKEN
</pre>
""",
    ),
    "build_file": attr.label(
        allow_single_file = True,
        doc =
            "The file to use as the BUILD file for this repository." +
            "This attribute is an absolute label (use '@//' for the main " +
            "repo). The file does not need to be named BUILD, but can " +
            "be (something like BUILD.new-repo-name may work well for " +
            "distinguishing it from the repository's actual BUILD files. " +
            "Either build_file or build_file_content can be specified, but " +
            "not both.",
    ),
    "build_file_content": attr.string(
        doc =
            "The content for the BUILD file for this repository. " +
            "Either build_file or build_file_content can be specified, but " +
            "not both.",
    ),
    "integrity": attr.string(
        doc = """Expected checksum in Subresource Integrity format of the file downloaded.

This must match the checksum of the file downloaded. _It is a security risk
to omit the checksum as remote files can change._ At best omitting this
field will make your build non-hermetic. It is optional to make development
easier but either this attribute or `sha256` should be set before shipping.""",
    ),
    "netrc": attr.string(
        doc = "Location of the .netrc file to use for authentication",
    ),
    "sha256": attr.string(
        doc = """The expected SHA-256 of the file downloaded.

This must match the SHA-256 of the file downloaded. _It is a security risk
to omit the SHA-256 as remote files can change._ At best omitting this
field will make your build non-hermetic. It is optional to make development
easier but either this attribute or `integrity` should be set before shipping.""",
    ),
    "strip_prefix": attr.string(
        doc = """A directory prefix to strip from the extracted files.

Many archives contain a top-level directory that contains all of the useful
files in archive. Instead of needing to specify this prefix over and over
in the `build_file`, this field can be used to strip it from all of the
extracted files.

For example, suppose you are using `foo-lib-latest.zip`, which contains the
directory `foo-lib-1.2.3/` under which there is a `WORKSPACE` file and are
`src/`, `lib/`, and `test/` directories that contain the actual code you
wish to build. Specify `strip_prefix = "foo-lib-1.2.3"` to use the
`foo-lib-1.2.3` directory as your top-level directory.

Note that if there are files outside of this directory, they will be
discarded and inaccessible (e.g., a top-level license file). This includes
files/directories that start with the prefix but are not in the directory
(e.g., `foo-lib-1.2.3.release-notes`). If the specified prefix does not
match a directory in the archive, Bazel will return an error.""",
    ),
    "urls": attr.string_list(
        doc = """A list of URLs to a file that will be made available to Bazel.

Each entry must be a file, http or https URL. Redirections are followed.
Authentication is not supported.

URLs are tried in order until one succeeds, so you should list local mirrors first.
If all downloads fail, the rule will fail.""",
        mandatory = True,
    ),
}

http_appimage = repository_rule(
    doc = """\
Download and extract a [`.appimage`](https://appimage.org/) file and extract it's
contents for use as a Bazel repository.
""",
    implementation = _http_appimage_impl,
    attrs = _ATTRS,
)
