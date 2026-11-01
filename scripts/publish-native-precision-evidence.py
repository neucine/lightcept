#!/usr/bin/env python3
"""Publish path-neutral local corpus reports and their precision comparison."""

import argparse
import hashlib
import json
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPARE = runpy.run_path(str(ROOT / "scripts/compare-native-precision.py"))["compare"]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normalize(value, corpus_root: Path, filenames: set[str]):
    if isinstance(value, dict):
        return {key: normalize(item, corpus_root, filenames) for key, item in value.items()}
    if isinstance(value, list):
        return [normalize(item, corpus_root, filenames) for item in value]
    if isinstance(value, str) and value.startswith(str(corpus_root) + "/"):
        path = Path(value)
        if path.parent != corpus_root or path.name not in filenames:
            raise ValueError(f"unexpected source path in report: {value}")
        return f"corpus/{path.name}"
    if isinstance(value, str) and value.startswith("/"):
        raise ValueError(f"unexpected absolute path in report: {value}")
    return value


def publish_report(source: Path, destination: Path, corpus_root: Path, filenames: set[str]) -> None:
    rows = [normalize(json.loads(line), corpus_root, filenames) for line in source.read_text().splitlines() if line.strip()]
    if not rows:
        raise ValueError(f"report has no rows: {source}")
    destination.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("macos_report", type=Path)
    parser.add_argument("macos_corpus", type=Path)
    parser.add_argument("linux_report", type=Path)
    parser.add_argument("linux_corpus", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    filenames = {entry["file"] for entry in json.loads((ROOT / "qualification/native-sources.json").read_text())["sources"]}
    args.output_dir.mkdir(parents=True, exist_ok=True)
    macos = args.output_dir / "macos-arm64.jsonl"
    linux = args.output_dir / "linux-aarch64.jsonl"
    publish_report(args.macos_report, macos, args.macos_corpus.absolute(), filenames)
    publish_report(args.linux_report, linux, args.linux_corpus.absolute(), filenames)
    result = COMPARE(macos, linux)
    comparison = args.output_dir / "precision-comparison.json"
    comparison.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({path.name: digest(path) for path in (macos, linux, comparison)}, sort_keys=True))


if __name__ == "__main__":
    main()
