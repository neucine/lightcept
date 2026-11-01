#!/usr/bin/env python3
"""Compare measured chart reports for spatial v4 and above-white v5."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
from pathlib import Path

SHARED = (
    "source_sha256", "storage_variant", "profile_sha256", "as_shot_neutral_sha256",
    "pipeline_source_sha256", "output_icc_sha256", "chart_sha256", "dimensions", "reference",
)


def load(path: Path, expected_highlight: str) -> dict:
    data = json.loads(path.read_text())
    verification = data.get("render_verification", {})
    if verification.get("method") != "exact-native-full-rerender-v1" or verification.get("highlight") != expected_highlight:
        raise ValueError(f"{path}: expected verified {expected_highlight} full render")
    if verification.get("demosaic") != "bilinear":
        raise ValueError(f"{path}: expected bilinear demosaic")
    if not isinstance(verification.get("exposure_ev"), (int, float)) or not math.isfinite(verification["exposure_ev"]):
        raise ValueError(f"{path}: invalid exposure")
    if verification.get("render_sha256") != data.get("render_sha256"):
        raise ValueError(f"{path}: verified render digest differs from report")
    if not isinstance(data.get("patches"), list) or not data["patches"]:
        raise ValueError(f"{path}: missing measured patches")
    stages = data.get("render_components")
    if not isinstance(stages, list) or not stages:
        raise ValueError(f"{path}: missing ordered stages")
    return data


def compare(v4: dict, v5: dict) -> dict:
    for field in SHARED:
        if v4.get(field) != v5.get(field):
            raise ValueError(f"reports differ in {field}")
    a, b = v4["render_verification"], v5["render_verification"]
    if a["exposure_ev"] != b["exposure_ev"] or a["demosaic"] != b["demosaic"]:
        raise ValueError("reports differ in exposure or demosaic")
    stages4, stages5 = v4["render_components"], v5["render_components"]
    if len(stages4) != len(stages5) or [s.get("stage") for s in stages4] != [s.get("stage") for s in stages5]:
        raise ValueError("reports differ in ordered stage layout")
    for original, changed in zip(stages4, stages5):
        if original["stage"] == "sensor":
            if (original.get("algorithm"), original.get("version")) != ("dng-active-area-black-white", 1):
                raise ValueError("v4 lacks clamped sensor identity")
            if (changed.get("algorithm"), changed.get("version")) != ("dng-active-area-black-white-retained-headroom", 2):
                raise ValueError("v5 lacks retained-headroom sensor identity")
            if original == changed:
                raise ValueError("sensor identities are identical")
            if {k: v for k, v in original.items() if k not in ("algorithm", "version")} != {
                k: v for k, v in changed.items() if k not in ("algorithm", "version")
            }:
                raise ValueError("reports differ in sensor stage metadata")
        elif original != changed:
            raise ValueError(f"reports differ in {original['stage']} stage")
    if not any(stage.get("stage") == "sensor" for stage in stages4):
        raise ValueError("reports lack sensor stage")
    patches4 = {p["id"]: p for p in v4["patches"]}
    patches5 = {p["id"]: p for p in v5["patches"]}
    if len(patches4) != len(v4["patches"]) or len(patches5) != len(v5["patches"]) or patches4.keys() != patches5.keys():
        raise ValueError("reports have different or duplicate patch IDs")
    rows = []
    for ident in sorted(patches4):
        old, new = patches4[ident], patches5[ident]
        for field in ("role", "sample_pixels", "measured_lab_d50"):
            if old.get(field) != new.get(field):
                raise ValueError(f"patch {ident} differs in {field}")
        old_error, new_error = old["delta_e_2000"], new["delta_e_2000"]
        if any(not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 for value in (old_error, new_error)):
            raise ValueError(f"patch {ident} has invalid color error")
        rows.append({"id": ident, "role": old["role"], "v4_delta_e_2000": old_error,
                     "v5_delta_e_2000": new_error, "change_delta_e_2000": round(new_error - old_error, 4),
                     "v4_clipped_pixel_fraction": old["clipped_pixel_fraction"],
                     "v5_clipped_pixel_fraction": new["clipped_pixel_fraction"]})
    roles = {role: [row for row in rows if row["role"] == role] for role in ("neutral", "chromatic", "near-saturation")}
    return {"source_sha256": v4["source_sha256"], "chart_sha256": v4["chart_sha256"],
            "profile_sha256": v4["profile_sha256"], "pipeline_source_sha256": v4["pipeline_source_sha256"],
            "exposure_ev": a["exposure_ev"], "v4_render_sha256": v4["render_sha256"],
            "v5_render_sha256": v5["render_sha256"], "patches": rows,
            "by_role": {role: {"patch_count": len(items),
                               "median_change_delta_e_2000": round(statistics.median(item["change_delta_e_2000"] for item in items), 4)
                               if items else None,
                               "worsened_patch_count": sum(item["change_delta_e_2000"] > 0 for item in items)}
                        for role, items in roles.items()}}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("v4_report", type=Path)
    parser.add_argument("v5_report", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    v4 = load(args.v4_report, "spatial-v4")
    v5 = load(args.v5_report, "spatial-headroom-v5")
    result = compare(v4, v5)
    result["v4_report_sha256"] = hashlib.sha256(args.v4_report.read_bytes()).hexdigest()
    result["v5_report_sha256"] = hashlib.sha256(args.v5_report.read_bytes()).hexdigest()
    encoded = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded)
    print(encoded, end="")


if __name__ == "__main__":
    main()
