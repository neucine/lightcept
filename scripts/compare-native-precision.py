#!/usr/bin/env python3
"""Compare complete native qualification JSONL reports from distinct platforms.

Identical output hashes prove a zero encoded-channel delta for the measured
previews and TIFF exports. A mismatch has no numeric error bound from hashes;
retain the files and compare decoded pixels before assigning one.
"""

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path


def valid_digest(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def valid_dimensions(value: object) -> bool:
    return isinstance(value, list) and len(value) == 2 and all(type(side) is int and side > 0 for side in value)


def read_report(path: Path) -> tuple[dict, dict]:
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    environment_rows = [row["precision_environment"] for row in rows if "precision_environment" in row]
    if len(environment_rows) != 1:
        raise ValueError(f"{path}: expected one execution environment")
    if any("id" in row and row.get("match") is not True for row in rows):
        raise ValueError(f"{path}: qualification contains a failed or missing check")
    sources = {}
    for row in rows:
        source_id = row.get("id")
        if source_id is None:
            continue
        if "candidate_contract" in row:
            candidate = row["candidate_contract"]
            if candidate.get("precisionBound") is not None:
                raise ValueError(f"{path}: candidate {source_id} unexpectedly claims a precision bound")
            if "candidate" in sources.get(source_id, {}):
                raise ValueError(f"{path}: duplicate candidate for {source_id}")
            sources.setdefault(source_id, {})["candidate"] = candidate
        elif "provenance" in row:
            if "provenance" in sources.get(source_id, {}):
                raise ValueError(f"{path}: duplicate provenance for {source_id}")
            sources.setdefault(source_id, {})["provenance"] = row["provenance"]
        elif "max_rgb8_channel_delta" in row:
            if row["max_rgb8_channel_delta"] != 0 or not row["match"]:
                raise ValueError(f"{path}: preview repeatability failed for {source_id}")
            if not valid_dimensions(row.get("preview_dimensions")) or not valid_digest(row.get("preview_sha256")) or row.get("repeated_sha256") != row["preview_sha256"]:
                raise ValueError(f"{path}: invalid or unequal repeated preview for {source_id}")
            exposure = float(row["exposure_ev"])
            if not math.isfinite(exposure):
                raise ValueError(f"{path}: invalid preview exposure for {source_id}")
            previews = sources.setdefault(source_id, {}).setdefault("previews", {})
            if exposure in previews:
                raise ValueError(f"{path}: duplicate preview exposure {exposure} for {source_id}")
            previews[exposure] = (
                row["preview_dimensions"], row["preview_sha256"]
            )
        elif row.get("export_format") == "RGB16 TIFF":
            if row["max_rgb16_channel_delta"] != 0 or not row["match"]:
                raise ValueError(f"{path}: export repeatability failed for {source_id}")
            if (row.get("exposure_ev") != 0.0 or not valid_dimensions(row.get("dimensions"))
                    or not valid_digest(row.get("export_sha256")) or row.get("repeated_sha256") != row["export_sha256"]):
                raise ValueError(f"{path}: invalid or unequal repeated export for {source_id}")
            source = sources.setdefault(source_id, {})
            if "export" in source:
                raise ValueError(f"{path}: duplicate export for {source_id}")
            source["export"] = (row["exposure_ev"], row["dimensions"], row["export_sha256"])
    for source_id, source in sources.items():
        if "candidate" not in source:
            continue
        if "provenance" not in source or set(source.get("previews", {})) != {-2.0, 0.0, 2.0} or "export" not in source:
            raise ValueError(f"{path}: incomplete precision evidence for {source_id}")
        if source["candidate"]["source"]["sha256"] != source["provenance"]["source_sha256"]:
            raise ValueError(f"{path}: source identity mismatch for {source_id}")
    return environment_rows[0], {source_id: source for source_id, source in sources.items() if "candidate" in source}


def compare(first_path: Path, second_path: Path) -> dict:
    first_environment, first_sources = read_report(first_path)
    second_environment, second_sources = read_report(second_path)
    first_platform = (first_environment["system"], first_environment["machine"])
    second_platform = (second_environment["system"], second_environment["machine"])
    if first_platform == second_platform:
        raise ValueError("both reports use the same OS and architecture; this is not a cross-platform comparison")
    if first_environment["cyna_toolchain_lock_sha256"] != second_environment["cyna_toolchain_lock_sha256"]:
        raise ValueError("reports use different Cyna toolchain locks")
    if not first_sources or first_sources.keys() != second_sources.keys():
        raise ValueError("reports do not cover the same renderable source IDs")
    compared = []
    measured_outputs = {}
    for source_id in sorted(first_sources):
        first = first_sources[source_id]
        second = second_sources[source_id]
        for field in ("source_sha256", "source_bytes", "storage_variant", "embedded_profile_sha256", "as_shot_neutral_sha256", "pipeline_source_sha256", "output_icc_sha256", "components"):
            if first["provenance"][field] != second["provenance"][field]:
                raise ValueError(f"{source_id}: {field} differs between reports")
        if first["candidate"] != second["candidate"]:
            raise ValueError(f"{source_id}: candidate render contracts differ between reports")
        if first["previews"] != second["previews"]:
            raise ValueError(f"{source_id}: at least one encoded RGB8 preview differs; hashes cannot quantify its channel error")
        if first["export"] != second["export"]:
            raise ValueError(f"{source_id}: encoded RGB16 TIFF differs; hashes cannot quantify its channel error")
        compared.append(source_id)
        measured_outputs[source_id] = {
            "source_sha256": first["provenance"]["source_sha256"],
            "storage_variant": first["provenance"]["storage_variant"],
            "embedded_profile_sha256": first["provenance"]["embedded_profile_sha256"],
            "pipeline_source_sha256": first["provenance"]["pipeline_source_sha256"],
            "output_icc_sha256": first["provenance"]["output_icc_sha256"],
            "render_components": first["provenance"]["components"],
            "previews": [
                {"exposure_ev": exposure, "dimensions": first["previews"][exposure][0],
                 "sha256": first["previews"][exposure][1]}
                for exposure in sorted(first["previews"])
            ],
            "export": {"exposure_ev": first["export"][0], "dimensions": first["export"][1],
                       "sha256": first["export"][2]},
        }
    return {
        "schema_version": 1,
        "platforms": [first_platform, second_platform],
        "report_sha256": [hashlib.sha256(first_path.read_bytes()).hexdigest(),
                          hashlib.sha256(second_path.read_bytes()).hexdigest()],
        "cyna_toolchain_lock_sha256": first_environment["cyna_toolchain_lock_sha256"],
        "source_ids": compared,
        "measured_outputs": measured_outputs,
        "measured_preview_rgb8_max_channel_delta": 0,
        "measured_export_rgb16_max_channel_delta": 0,
        "scope": "only the pinned output dimensions and exposure values in both reports",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first", type=Path)
    parser.add_argument("second", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(compare(args.first, args.second), sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
