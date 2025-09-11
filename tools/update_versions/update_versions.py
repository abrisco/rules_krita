"""A tool for fetching the integrity values of all known versions of Krita"""

import argparse
import base64
import binascii
import json
import logging
import os
import re
import runpy
import time
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urljoin, urlparse

BASE_URL = "https://download.kde.org/Attic/krita/"

VERSION_DIR_REGEX = re.compile(r"([\d\.]+)/")

PLATFORM_PATTERNS = {
    "macos_aarch64": re.compile(r"^(?!.*-dmg\.dmg$).+\.dmg$"),
    "linux_x86_64": re.compile(r"^.*\.appimage$"),
    "windows_x86_64": re.compile(r"^(krita[_-]x64.*\d\.zip|.*x64\.zip)$"),
}

MACOS_UNIVERSAL_VERSIONS = [
    "4.4.3",
    "4.4.5",
    "4.4.7",
    "4.4.8",
]

REQUEST_HEADERS = {"User-Agent": "curl/8.7.1"}  # Set the User-Agent header

Versions = dict[str, dict[str, str]]

BUILD_TEMPLATE = """\
\"\"\"Krita Versions

A mapping of platform to url and integrity of the archive for said platform for each version of Krita available.
\"\"\"

# AUTO-GENERATED: DO NOT MODIFY
#
# Update using the following command:
#
# ```
# bazel run //tools/update_versions
# ```

KRITA_VERSIONS = {}
"""


def parse_args() -> argparse.Namespace:
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description=__doc__)

    repo_root = Path(__file__).parent.parent.parent
    if "BUILD_WORKSPACE_DIRECTORY" in os.environ:
        repo_root = Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])

    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "krita/private/versions.bzl",
        help="The path to write the versions bzl file to.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging",
    )

    return parser.parse_args()


class LinkParser(HTMLParser):
    """A class for parsing links from an HTML document."""

    def __init__(self) -> None:
        """The constructor."""
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        """Parse the start tag value of an element"""
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.links.append(href)


def list_directory_links(url: str) -> list[str]:
    """Parses an HTML directory index and returns all links."""
    req = urllib.request.Request(url, headers=REQUEST_HEADERS)
    max_retries = 3
    for i in range(max_retries):
        try:
            with urllib.request.urlopen(req) as response:
                html = response.read().decode("utf-8")
            parser = LinkParser()
            parser.feed(html)
            return parser.links
        except URLError as exc:
            if i == max_retries:
                raise
            logging.warning(exc)
            logging.info("Retrying")
            time.sleep(1)

    raise RuntimeError("Unreachable")


def download_sha256_hash(url: str) -> str:
    """Fetch the sha256 value for a given artifact url."""
    sha256_url = urlparse(str(url) + ".sha256")

    max_retries = 3
    for i in range(max_retries):
        try:
            logging.debug("Fetching sha256 file: %s", sha256_url.geturl())
            req = urllib.request.Request(sha256_url.geturl(), headers=REQUEST_HEADERS)
            with urllib.request.urlopen(req) as response:
                data = response.read()
                text = data.decode("utf-8").strip()
                sha256, _, _ = text.partition(" ")
                return sha256
        except URLError as exc:
            if i == max_retries:
                raise
            logging.warning(exc)
            logging.info("Retrying")
            time.sleep(1)

    raise RuntimeError("Unreachable")


def integrity(hex_str: str) -> str:
    """Convert a sha256 hex value to a Bazel integrity value"""

    # Remove any whitespace and convert from hex to raw bytes
    try:
        raw_bytes = binascii.unhexlify(hex_str.strip())
    except binascii.Error as e:
        raise ValueError(f"Invalid hex input: {e}") from e

    # Convert to base64
    encoded = base64.b64encode(raw_bytes).decode("utf-8")
    return f"sha256-{encoded}"


def load_existing_versions(path: Path) -> Versions:
    """Load a Python file as a module and return it."""
    symbols = runpy.run_path(str(path))
    if "KRITA_VERSIONS" not in symbols:
        raise KeyError(f"{path} does not define KRITA_VERSIONS")
    versions = symbols["KRITA_VERSIONS"]
    if not isinstance(versions, dict):
        raise TypeError(f"KRITA_VERSIONS must be a dict, got {type(versions).__name__}")
    return versions


def main() -> None:  # pylint: disable=too-many-locals,too-many-branches
    """The main entrypoint."""

    args = parse_args()

    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)
    else:
        logging.basicConfig(level=logging.INFO)

    output = {}
    version_dirs = []
    for link in list_directory_links(BASE_URL):
        regex = VERSION_DIR_REGEX.match(link)
        if regex:
            version_dirs.append(regex)

    logging.debug("Processing %s versions", len(version_dirs))

    for version_dir in version_dirs:  # pylint: disable=too-many-nested-blocks
        if version_dir.group(1) in output:
            continue
        logging.info("Processing %s", version_dir.group(1))
        version_url = urljoin(BASE_URL, version_dir.group(0))
        platform_data = {}
        filenames = sorted(set(list_directory_links(version_url)))
        for filename in filenames:
            for platform, regex in PLATFORM_PATTERNS.items():
                if platform in platform_data:
                    continue
                if "beta" in filename:
                    continue
                if "alpha" in filename:
                    continue
                if regex.match(filename):
                    # Prefer xz archives over gz
                    if filename.endswith(".gz"):
                        xz_name = filename.replace(".gz", ".xz")
                        if xz_name in filenames:
                            filename = xz_name
                    file_url = urljoin(version_url, filename)
                    logging.debug("Processing for %s - %s", platform, file_url)
                    platform_data[platform] = {
                        "artifact": filename,
                        "integrity": integrity(download_sha256_hash(file_url)),
                    }
                    break
        if platform_data:
            output[version_dir.group(1)] = platform_data

    x64_plat = "macos_x86_64"
    aarch64_plat = "macos_aarch64"
    for version in output:  # pylint: disable=consider-using-dict-items
        if aarch64_plat not in output[version]:
            continue
        if version.startswith(("1", "2", "3")) or (
            version.startswith("4") and version not in MACOS_UNIVERSAL_VERSIONS
        ):
            logging.debug("Mapping %s -> %s for %s", aarch64_plat, x64_plat, version)
            output[version][x64_plat] = output[version][aarch64_plat]
            del output[version][aarch64_plat]
            continue

        logging.debug("Duplicating %s -> %s for %s", aarch64_plat, x64_plat, version)
        output[version][x64_plat] = output[version][aarch64_plat]

    logging.debug("Writing to %s", args.output)

    args.output.write_text(BUILD_TEMPLATE.format(json.dumps(output, indent=4)))
    logging.info("Done")


if __name__ == "__main__":
    main()
