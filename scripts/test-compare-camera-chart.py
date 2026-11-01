#!/usr/bin/env python3
"""Paired measured-chart report checks."""

import copy
import runpy
import unittest
from pathlib import Path

compare = runpy.run_path(str(Path(__file__).with_name("compare-camera-chart.py")))["compare"]


def report(highlight):
    sensor = ("dng-active-area-black-white-retained-headroom", 2) if highlight == "spatial-headroom-v5" else ("dng-active-area-black-white", 1)
    return {
        "source_sha256": "a" * 64, "storage_variant": "sof3", "profile_sha256": "b" * 64,
        "as_shot_neutral_sha256": "c" * 64, "pipeline_source_sha256": "d" * 64,
        "output_icc_sha256": "e" * 64, "chart_sha256": "f" * 64,
        "dimensions": [4, 4], "reference": "measured target",
        "render_sha256": "1" * 64,
        "render_verification": {"method": "exact-native-full-rerender-v1", "highlight": highlight,
                                "demosaic": "bilinear", "exposure_ev": -2.0, "render_sha256": "1" * 64},
        "render_components": [{"stage": "sensor", "algorithm": sensor[0], "version": sensor[1]},
                              {"stage": "highlight", "algorithm": "spatial-camera-highlight-reconstruction", "version": 4}],
        "patches": [{"id": "neutral-1", "role": "neutral", "sample_pixels": 9,
                     "measured_lab_d50": [50, 0, 0], "delta_e_2000": 2.0,
                     "clipped_pixel_fraction": 0.0}],
    }


class ComparisonTest(unittest.TestCase):
    def test_same_capture_and_stage_variant(self):
        old, new = report("spatial-v4"), report("spatial-headroom-v5")
        new["patches"][0]["delta_e_2000"] = 1.5
        result = compare(old, new)
        self.assertEqual(result["by_role"]["neutral"]["median_change_delta_e_2000"], -0.5)
        self.assertEqual(result["by_role"]["neutral"]["worsened_patch_count"], 0)

    def test_rejects_mismatched_evidence(self):
        old, new = report("spatial-v4"), report("spatial-headroom-v5")
        changes = [
            ("chart_sha256", "0" * 64),
            ("source_sha256", "0" * 64),
            ("profile_sha256", "0" * 64),
        ]
        for field, value in changes:
            altered = copy.deepcopy(new)
            altered[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, field):
                compare(old, altered)
        new["render_verification"]["exposure_ev"] = 0.0
        with self.assertRaisesRegex(ValueError, "exposure"):
            compare(old, new)

    def test_rejects_stage_and_patch_changes(self):
        old, new = report("spatial-v4"), report("spatial-headroom-v5")
        altered = copy.deepcopy(new)
        altered["render_components"][1]["version"] = 5
        with self.assertRaisesRegex(ValueError, "highlight stage"):
            compare(old, altered)
        altered = copy.deepcopy(new)
        altered["patches"][0]["measured_lab_d50"] = [51, 0, 0]
        with self.assertRaisesRegex(ValueError, "measured_lab_d50"):
            compare(old, altered)
        altered = copy.deepcopy(new)
        altered["render_components"][0]["asset_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "sensor stage metadata"):
            compare(old, altered)


if __name__ == "__main__":
    unittest.main()
