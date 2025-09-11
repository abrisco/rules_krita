"""The process wrapper for `KritaExport` actions in Bazel."""

import argparse
import logging
import os
import platform
import subprocess
import sys
import tempfile
from pathlib import Path

RULES_KRITA_DEBUG = "RULES_KRITA_DEBUG"


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument(
        "--krita",
        type=Path,
        required=True,
        help="The path to the krita binary.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The output location of the desired export.",
    )
    parser.add_argument(
        "--kra_file",
        type=Path,
        required=True,
        help="The path to the `.kra` file.",
    )

    return parser.parse_args()


def mkdir(path: Path) -> Path:
    """Create the requested directory."""
    path.mkdir(exist_ok=True, parents=True)
    return path


def main() -> None:
    """The main entrypoint."""
    if RULES_KRITA_DEBUG in os.environ:
        logging.basicConfig(level=logging.DEBUG)

    args = parse_args()

    with tempfile.TemporaryDirectory(prefix="bzlkrita-") as tmp:
        tmp_path = Path(tmp)
        home = mkdir(tmp_path / "home")
        tmpdir = mkdir(tmp_path / "tmp")
        resources = mkdir(tmp_path / "resources")
        env = dict(os.environ)
        env.update(
            {
                "HOME": str(home),
                "USERPROFILE": str(home),
                "TMP": str(tmpdir),
                "TEMP": str(tmpdir),
                "TMPDIR": str(tmpdir),
            }
        )

        if platform.system() == "Linux":
            env["QT_QPA_PLATFORM"] = "offscreen"

        krita_args = [
            str(args.krita),
            "--resource-location",
            str(resources),
            str(args.kra_file),
            "--export",
            "--export-filename",
            str(args.output),
        ]

        logging.debug("Command: `%s`", " ".join(krita_args))
        result = subprocess.run(
            krita_args,
            env=env,
            check=False,
            stderr=subprocess.STDOUT,
            stdout=subprocess.PIPE,
        )

        if result.returncode or not args.output.exists:
            print(result.stdout.decode("utf-8"), file=sys.stderr)
            sys.exit(result.returncode or 1)


if __name__ == "__main__":
    main()
