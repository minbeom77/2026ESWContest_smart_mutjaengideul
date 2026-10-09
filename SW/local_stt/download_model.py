"""Download pinned int8 weights and verify weights and vocabulary."""
import argparse
import hashlib
from pathlib import Path
import urllib.request

REVISION = "f0e73b1653c3ea75898c6d949dd71c690c9121da"
BASE = ("https://huggingface.co/kangkyu/icefall-asr-ko-streaming-zipformer-174m"
        f"/resolve/{REVISION}/")
FILES = {
    "encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx":
        "e595e2e37f46078387868ffa656b775de787fa511cf851cf8e1892d7dbdabe54",
    "decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx":
        "f5dfa6c8609b29da86c739d4904889475c33b62e28e70c619952a0ee6c31416f",
    "joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx":
        "64efd9aeb71fb2278c713b3d5eb5ec45edf6b2ccd8716d3709044f17723c13fd",
    "tokens.txt": "435dfb9e0a2b6a79124f1a4d8f0f33a951b25384726e2e0d854f081533e6ec9d",
}


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def download(destination):
    destination.mkdir(parents=True, exist_ok=True)
    for name in [*FILES, "README.md", "README_ko.md", "SHA256SUMS"]:
        target = destination / name
        expected = FILES.get(name)
        if target.exists() and expected and digest(target) == expected:
            continue
        pending = target.with_suffix(target.suffix + ".part")
        with urllib.request.urlopen(BASE + name, timeout=60) as response:
            with pending.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
        if expected and digest(pending) != expected:
            raise RuntimeError(f"Model checksum mismatch: {name}")
        pending.replace(target)
        print(name, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", type=Path, default=Path("korean-streaming-174m"))
    download(parser.parse_args().destination)
