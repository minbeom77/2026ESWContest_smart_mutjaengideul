import json
import socket
import struct
import threading
import unittest
from controller import envelope, publish, read_packet


class ControllerTests(unittest.TestCase):
    def test_manual_envelope_never_fabricates_a_model_score(self):
        for fall in (True, False):
            event = envelope(fall, now=123)
            self.assertEqual(event['device'], 'safehub_manual_demo')
            self.assertEqual(event['confidence'], 0)
            self.assertEqual(event['timestamp'], 123)
            self.assertEqual(len(event), 6)
        self.assertNotEqual(envelope(True)['message_id'], envelope(True)['message_id'])

    def test_real_loopback_publish_waits_for_ack_and_never_retains(self):
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0))
            server.listen(1)
            captured = []
            def broker():
                with server.accept()[0] as connection:
                    connection.settimeout(3)
                    captured.append(read_packet(connection)[0])
                    # Fragment the response, as a real TCP stream may do.
                    connection.sendall(b'\x20\x02')
                    connection.sendall(b'\x00\x00')
                    kind, body = read_packet(connection)
                    captured.append(kind)
                    size = struct.unpack('!H', body[:2])[0]
                    captured.append(body[2:2 + size].decode())
                    captured.append(json.loads(body[4 + size:]))
                    connection.sendall(b'\x40\x02\x00\x01')
                    captured.append(read_packet(connection)[0])
            thread = threading.Thread(target=broker)
            thread.start()
            payload = envelope(True)
            publish('127.0.0.1', server.getsockname()[1], payload)
            thread.join(4)
            self.assertFalse(thread.is_alive())
            self.assertEqual(captured, [0x10, 0x32, 'safehub/csi/bedroom/event', payload, 0xe0])


if __name__ == '__main__':
    unittest.main()
