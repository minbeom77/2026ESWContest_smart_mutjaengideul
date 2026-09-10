import unittest

import numpy as np

from frame_hands_adapter import FrameHandsError, frame_hands_from_result


def hand(raw, physical, value=1.0, confidence=0.9):
    model = "RIGHT" if raw > 0.5 else "LEFT"
    return {
        "handedness_raw": raw,
        "model_hand": model,
        "physical_hand": physical,
        "hand_confidence": confidence,
        "landmarks_xy": np.full((21, 2), value, dtype=np.float32).tolist(),
    }


class FrameHandsAdapterTest(unittest.TestCase):
    def test_unflipped_model_right_maps_to_physical_left(self):
        left, right = frame_hands_from_result(
            {"mirror_input": False, "hands": [hand(0.735, "LEFT")]}
        )
        self.assertEqual(left.shape, (21, 2))
        self.assertIsNone(right)

    def test_mirrored_model_right_stays_physical_right(self):
        left, right = frame_hands_from_result(
            {"mirror_input": True, "hands": [hand(0.735, "RIGHT")]}
        )
        self.assertIsNone(left)
        self.assertEqual(right.shape, (21, 2))

    def test_higher_confidence_duplicate_wins(self):
        left, _ = frame_hands_from_result(
            {
                "mirror_input": False,
                "hands": [
                    hand(0.8, "LEFT", value=1.0, confidence=0.7),
                    hand(0.9, "LEFT", value=2.0, confidence=0.95),
                ],
            }
        )
        np.testing.assert_array_equal(left, np.full((21, 2), 2.0))

    def test_rejects_inconsistent_physical_hand(self):
        with self.assertRaises(FrameHandsError):
            frame_hands_from_result(
                {"mirror_input": False, "hands": [hand(0.735, "RIGHT")]}
            )

    def test_rejects_bad_landmark_shape(self):
        bad = hand(0.735, "LEFT")
        bad["landmarks_xy"] = [[0.0, 0.0]]
        with self.assertRaises(FrameHandsError):
            frame_hands_from_result({"mirror_input": False, "hands": [bad]})


if __name__ == "__main__":
    unittest.main()
