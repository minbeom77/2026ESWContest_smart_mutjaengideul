class MockPredictor:
    """실제 GRU 모델 연결 전 파이프라인 검증용 예측기."""

    def predict(self, sequence):
        if not sequence:
            return None

        return "안녕하세요"
