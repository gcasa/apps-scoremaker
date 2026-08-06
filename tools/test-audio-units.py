#!/usr/bin/env python3
# Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
#
# This file is part of ScoreMaker and is distributed under the GNU Lesser
# General Public License, version 2.1 or later.

"""Validate every installed Audio Unit music device with a bounded timeout."""

import json
import re
import subprocess
import sys


COMPONENT_PATTERN = re.compile(
    r"^\s*(?P<type>.{4})\s+(?P<subtype>.{4})\s+(?P<manufacturer>.{4})\s+-\s+(?P<name>.+)$"
)


def installed_instruments():
    listing = subprocess.run(
        ["/usr/bin/auval", "-a"], capture_output=True, check=True, text=True
    ).stdout
    for line in listing.splitlines():
        match = COMPONENT_PATTERN.match(line)
        if match and match.group("type") == "aumu":
            yield match.groupdict()


def validate(component, timeout):
    command = [
        "/usr/bin/auval",
        "-v",
        component["type"],
        component["subtype"],
        component["manufacturer"],
    ]
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout
        )
        return {
            **component,
            "status": "passed" if result.returncode == 0 else "failed",
            "exitCode": result.returncode,
            "diagnostic": (result.stdout + result.stderr)[-4000:],
        }
    except subprocess.TimeoutExpired as error:
        return {
            **component,
            "status": "timeout",
            "exitCode": None,
            "diagnostic": str(error),
        }


def main():
    timeout = float(sys.argv[1]) if len(sys.argv) > 1 else 30.0
    report = [validate(component, timeout) for component in installed_instruments()]
    print(json.dumps({"formatVersion": 1, "audioUnits": report}, indent=2))
    return 1 if any(item["status"] != "passed" for item in report) else 0


if __name__ == "__main__":
    raise SystemExit(main())
