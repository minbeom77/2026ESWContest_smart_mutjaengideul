def process_sequence(sequence, predictor, sender):
    """관절 시퀀스를 번역하고 MQTT로 전송한다."""
    translation = predictor.predict(sequence)

    if translation is None:
        return None

    sender.connect()

    try:
        sender.publish_translation(translation)
    finally:
        sender.disconnect()

    return translation
