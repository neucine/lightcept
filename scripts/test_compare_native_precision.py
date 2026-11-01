#!/usr/bin/env python3
"""Behavior checks for the cross-platform precision report comparator."""

import json
import runpy
import tempfile
import unittest
from pathlib import Path


COMPARE = runpy.run_path(str(Path(__file__).with_name("compare-native-precision.py")))["compare"]


def report(system: str, preview_hash: str = "a" * 64, export_hash: str = "b" * 64) -> list[dict]:
    source = "example-camera"
    return [
        {"precision_environment": {"system": system, "machine": "arm64", "cyna_toolchain_lock_sha256": "lock"}},
        {"id": source, "provenance": {
            "source_sha256": "source", "source_bytes": 100, "storage_variant": "sof3",
            "embedded_profile_sha256": "profile", "as_shot_neutral_sha256": "neutral",
            "pipeline_source_sha256": "pipeline", "output_icc_sha256": "icc", "components": ["stage"],
        }, "match": True},
        {"id": source, "candidate_contract": {"source": {"sha256": "source"}}, "match": True},
        *[
            {"id": source, "exposure_ev": ev, "preview_dimensions": [1200, 800],
             "preview_sha256": preview_hash, "repeated_sha256": preview_hash, "max_rgb8_channel_delta": 0, "match": True}
            for ev in (-2.0, 0.0, 2.0)
        ],
        {"id": source, "export_format": "RGB16 TIFF", "exposure_ev": 0.0, "dimensions": [6000, 4000],
         "export_sha256": export_hash, "repeated_sha256": export_hash, "max_rgb16_channel_delta": 0, "match": True},
    ]


class PrecisionComparisonTests(unittest.TestCase):
    def compare_reports(self, first: list[dict], second: list[dict]) -> dict:
        with tempfile.TemporaryDirectory() as directory:
            first_path = Path(directory) / "first.jsonl"
            second_path = Path(directory) / "second.jsonl"
            for path, rows in ((first_path, first), (second_path, second)):
                path.write_text("\n".join(json.dumps(row) for row in rows) + "\n")
            return COMPARE(first_path, second_path)

    def test_identical_outputs_on_distinct_platforms_have_zero_measured_delta(self) -> None:
        result = self.compare_reports(report("Darwin"), report("Linux"))
        self.assertEqual(result["measured_preview_rgb8_max_channel_delta"], 0)
        self.assertEqual(result["measured_export_rgb16_max_channel_delta"], 0)
        self.assertEqual(len(result["report_sha256"]), 2)
        measured = result["measured_outputs"]["example-camera"]
        self.assertEqual(measured["render_components"], ["stage"])
        self.assertEqual([row["exposure_ev"] for row in measured["previews"]], [-2.0, 0.0, 2.0])
        self.assertEqual((measured["storage_variant"], measured["embedded_profile_sha256"], measured["output_icc_sha256"]), ("sof3", "profile", "icc"))

    def test_changed_output_has_no_inferred_numeric_bound(self) -> None:
        with self.assertRaisesRegex(ValueError, "hashes cannot quantify"):
            self.compare_reports(report("Darwin"), report("Linux", export_hash="c" * 64))

    def test_missing_pass_and_unequal_repeat_hashes_are_rejected(self) -> None:
        missing_pass = report("Linux")
        del missing_pass[3]["match"]
        with self.assertRaisesRegex(ValueError, "failed or missing check"):
            self.compare_reports(report("Darwin"), missing_pass)
        unequal_repeat = report("Linux")
        unequal_repeat[3]["repeated_sha256"] = "c" * 64
        with self.assertRaisesRegex(ValueError, "unequal repeated preview"):
            self.compare_reports(report("Darwin"), unequal_repeat)

    def test_invalid_dimensions_and_export_exposure_are_rejected(self) -> None:
        zero_width = report("Linux")
        zero_width[3]["preview_dimensions"] = [0, 800]
        with self.assertRaisesRegex(ValueError, "invalid or unequal repeated preview"):
            self.compare_reports(report("Darwin"), zero_width)
        wrong_exposure = report("Linux")
        wrong_exposure[-1]["exposure_ev"] = 1.0
        with self.assertRaisesRegex(ValueError, "invalid or unequal repeated export"):
            self.compare_reports(report("Darwin"), wrong_exposure)

    def test_same_platform_does_not_count_as_cross_platform(self) -> None:
        with self.assertRaisesRegex(ValueError, "same OS and architecture"):
            self.compare_reports(report("Darwin"), report("Darwin"))

    def test_incomplete_report_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "incomplete precision evidence"):
            self.compare_reports(report("Darwin")[:-1], report("Linux"))

    def test_changed_stage_identity_is_rejected(self) -> None:
        second = report("Linux")
        second[1]["provenance"]["components"] = ["different-stage"]
        with self.assertRaisesRegex(ValueError, "components differs"):
            self.compare_reports(report("Darwin"), second)

    def test_duplicate_exposure_is_rejected(self) -> None:
        second = report("Linux")
        second.insert(4, second[3].copy())
        with self.assertRaisesRegex(ValueError, "duplicate preview exposure"):
            self.compare_reports(report("Darwin"), second)


if __name__ == "__main__":
    unittest.main()
