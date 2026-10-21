from __future__ import annotations

import unittest

from tools.jasondocs.godot_static import SceneNode


class GodotStaticTests(unittest.TestCase):
    def test_scene_property_distinguishes_null_from_the_string_null(self) -> None:
        node = SceneNode(
            name="Connection",
            parent=".",
            header="",
            attrs={},
            block='keyword = null\nlabel = "null"\n',
        )

        self.assertIsNone(node.prop("keyword"))
        self.assertEqual(node.prop("label"), "null")


if __name__ == "__main__":
    unittest.main()
