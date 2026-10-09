"""Fake-clock evidence; these tests do not suspend the computer."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from soak_bridge import SoakClock, SoakInterrupted


class SoakClockTests(unittest.TestCase):
    def setUp(self):
        self.wall = self.awake = 100.0
        self.clock = SoakClock(3600, lambda: self.wall, lambda: self.awake)

    def advance(self, wall, awake=None):
        self.wall += wall
        self.awake += wall if awake is None else awake

    def test_normal_build_delay_is_not_called_suspend(self):
        self.advance(1.657)
        self.clock.check()
        self.assertEqual(list(self.clock.events), [])
        self.assertEqual(self.clock.suspended_seconds, 0)

    def test_three_second_gap_is_recorded_but_not_classified_as_suspend(self):
        self.advance(4)
        self.clock.check()
        self.assertEqual(self.clock.events[-1]['reason'], 'unobserved_gap')
        self.assertEqual(self.clock.events[-1]['suspend_seconds_from_clocks'], 0)

    def test_dual_clock_sleep_evidence_interrupts(self):
        self.advance(4453.5, .02)
        with self.assertRaises(SoakInterrupted) as caught:
            self.clock.check()
        self.assertEqual(caught.exception.details['reason'], 'suspend')
        self.assertAlmostEqual(self.clock.suspended_seconds, 4453.48)
        self.assertEqual(self.clock.remaining(), 0)

    def test_long_delay_without_sleep_evidence_stays_unattributed(self):
        self.advance(50)
        with self.assertRaises(SoakInterrupted) as caught:
            self.clock.check()
        self.assertEqual(caught.exception.details['reason'], 'unobserved_gap')

    def test_without_awake_clock_a_gap_does_not_prove_suspend(self):
        clock = SoakClock(30, lambda: self.wall)
        self.advance(40)
        with self.assertRaises(SoakInterrupted) as caught:
            clock.check()
        self.assertEqual(caught.exception.details['reason'], 'unobserved_gap')
        self.assertIsNone(caught.exception.details['awake_gap_seconds'])

    def test_clock_reversal_is_not_mistaken_for_valid_elapsed_time(self):
        self.advance(-5)
        with self.assertRaises(SoakInterrupted) as caught:
            self.clock.check()
        self.assertEqual(caught.exception.details['reason'], 'clock_discontinuity')

    def test_observation_history_is_bounded(self):
        for _ in range(25):
            self.advance(4)
            self.clock.check()
        self.assertEqual(len(self.clock.events), 20)


if __name__ == '__main__':
    unittest.main(verbosity=2)
