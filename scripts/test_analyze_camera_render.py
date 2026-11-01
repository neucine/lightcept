import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("analyze_camera_render", Path(__file__).with_name("analyze-camera-render.py"))
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class RegionSelectionTests(unittest.TestCase):
    def test_sparse_clipped_highlight_is_not_lost_to_mean_brightness(self):
        width, height, tile = 64, 32, 32
        rgb = bytearray([20, 20, 20] * (width * height))
        for row in range(height):
            for column in range(tile, width):
                at = (row * width + column) * 3
                rgb[at:at + 3] = bytes([150, 150, 150])
        rgb[(1 * width + 1) * 3:(1 * width + 1) * 3 + 3] = bytes([255, 255, 255])
        selected = module.selected_tiles(bytes(rgb), width, height, tile)
        self.assertEqual(selected["brightest_available"]["x"], 32)
        self.assertEqual(selected["highlight_stress"]["x"], 0)


if __name__ == "__main__":
    unittest.main()
