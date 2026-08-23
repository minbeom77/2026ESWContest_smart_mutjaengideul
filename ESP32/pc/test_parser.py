import unittest

from csi_capture import CSIParser


class CSIParserTest(unittest.TestCase):
    def test_starter_format(self):
        parser = CSIParser()
        parser.parse(
            "type,seq,mac,rssi,rate,noise_floor,channel,local_timestamp,"
            "sig_len,rx_format,len,first_word,data"
        )
        frame = parser.parse(
            'CSI_DATA,7,aa:bb:cc:dd:ee:ff,-42,11,-95,6,123456,64,1,4,0,"[3,4,5,12]"'
        )
        self.assertIsNotNone(frame)
        assert frame is not None
        self.assertEqual(frame.seq, 7)
        self.assertEqual(frame.channel, 6)
        self.assertEqual(frame.data, [3, 4, 5, 12])
        amplitudes = frame.amplitude_db_centered()
        self.assertEqual(amplitudes.size, 2)

    def test_headerless_compatibility_format(self):
        parser = CSIParser()
        frame = parser.parse(
            'CSI_DATA,8,aa:bb:cc:dd:ee:ff,-40,11,-96,32,4,11,372852,47,1,4,0,"[1,2,3,4]"'
        )
        self.assertIsNotNone(frame)
        assert frame is not None
        self.assertEqual(frame.channel, 11)
        self.assertEqual(frame.device_timestamp, 372852)
        self.assertEqual(frame.reported_len, 4)

    def test_non_csi_line(self):
        self.assertIsNone(CSIParser().parse("I (123) boot: hello"))


if __name__ == "__main__":
    unittest.main()
