from __future__ import annotations

import argparse
import json
from pathlib import Path

from .validation import PetPackValidationError, PetPackValidator


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a PetPack 1.0 archive")
    parser.add_argument("package", type=Path, help="path to one .petpack file")
    args = parser.parse_args()

    try:
        report = PetPackValidator().validate(args.package)
    except PetPackValidationError as error:
        print(json.dumps(error.as_dict(), ensure_ascii=False, sort_keys=True))
        return 2

    print(json.dumps(report.as_dict(), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
