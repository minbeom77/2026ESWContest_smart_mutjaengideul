from predictor import MockPredictor


def test_predict_returns_translation_for_sequence():
    predictor = MockPredictor()

    dummy_sequence = [
        [[0.1, 0.2, 0.3] for _ in range(21)]
    ]

    assert predictor.predict(dummy_sequence) == "안녕하세요"


def test_predict_returns_none_for_empty_sequence():
    predictor = MockPredictor()

    assert predictor.predict([]) is None
