"""Offline prototype for converting accepted CSI results into MQTT envelopes.

No network, model loading, serial access, or actuator control is performed.
Label mapping and reset policy must be supplied explicitly by the caller.
"""

import math
import uuid
from collections.abc import Mapping


class CsiEventAdapter:
    def __init__(self, *, room, device, fall_labels, normal_labels,
                 normal_confirmations):
        if room not in {"bedroom", "bathroom"}:
            raise ValueError("room must be bedroom or bathroom")
        if not isinstance(device, str) or not device.strip():
            raise ValueError("device must be a nonempty string")
        if isinstance(fall_labels, str) or isinstance(normal_labels, str):
            raise ValueError("labels must be collections of strings")
        fall_labels, normal_labels = set(fall_labels), set(normal_labels)
        labels = fall_labels | normal_labels
        if (not fall_labels or not normal_labels
                or any(not isinstance(x, str) or not x.strip() for x in labels)
                or "판단 보류" in labels
                or fall_labels & normal_labels):
            raise ValueError("explicit, disjoint fall and normal labels required")
        if type(normal_confirmations) is not int or normal_confirmations < 1:
            raise ValueError("normal_confirmations must be a positive integer")
        self.topic = f"safehub/csi/{room}/event"
        self.device = device.strip()
        self.fall_labels = fall_labels
        self.normal_labels = normal_labels
        self.normal_confirmations = normal_confirmations
        self._active = False
        self._normal_count = 0

    def update(self, result, *, timestamp):
        """Return an envelope on a new fall episode, otherwise None.

        timestamp is host Unix seconds, never CSI device_time.
        Reusing the returned envelope preserves its ID for future retries.
        Generation is not acknowledgement or proof of MQTT delivery.
        """
        if type(timestamp) is not int or timestamp < 0:
            raise ValueError("timestamp must be nonnegative integer Unix seconds")
        if not isinstance(result, Mapping):
            self._normal_count = 0
            return None
        label = result.get("label")
        scores = result.get("scores")
        if (not isinstance(label, str)
                or label not in self.fall_labels | self.normal_labels
                or not isinstance(scores, Mapping)):
            self._normal_count = 0
            return None
        score = scores.get(label)
        if (type(score) not in {int, float} or not math.isfinite(score)
                or not 0 <= score <= 1):
            self._normal_count = 0
            return None
        if label in self.normal_labels:
            self._normal_count += 1
            if self._normal_count >= self.normal_confirmations:
                self._active = False
                self._normal_count = self.normal_confirmations
            return None
        self._normal_count = 0
        if self._active:
            return None
        envelope = {
            "topic": self.topic,
            "qos": 1,
            "retain": False,
            "payload": {
                "message_id": str(uuid.uuid4()),
                "device": self.device,
                "event": "fall_detected",
                "confidence": float(score),
                "priority": 9,
                "timestamp": timestamp,
            },
        }
        self._active = True
        return envelope
