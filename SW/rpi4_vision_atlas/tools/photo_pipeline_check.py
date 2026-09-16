import argparse
import ast
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

import cv2 as cv
import numpy as np
import onnxruntime as ort


def session(path):
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    return ort.InferenceSession(
        str(path), sess_options=options,
        providers=["CPUExecutionProvider"])


def load_anchors(output):
    url = "https://raw.githubusercontent.com/opencv/opencv_zoo/main/models/palm_detection_mediapipe/mp_palmdet.py"
    with urlopen(url, timeout=30) as response:
        source = response.read()
    # Save the exact reference used; parse numbers without executing it.
    (output / "mp_palmdet_reference.py").write_bytes(source)
    tree = ast.parse(source.decode("utf-8"))
    cls = next(n for n in tree.body
               if isinstance(n, ast.ClassDef) and n.name == "MPPalmDet")
    fn = next(n for n in cls.body
              if isinstance(n, ast.FunctionDef) and n.name == "_load_anchors")
    ret = next(n for n in fn.body if isinstance(n, ast.Return))
    anchors = np.array(ast.literal_eval(ret.value.args[0]))
    assert anchors.shape == (2016, 2), anchors.shape
    np.save(output / "anchors.npy", anchors)
    return anchors, hashlib.sha256(source).hexdigest()


def nms(boxes, scores, threshold=0.3):
    # boxes: x1,y1,x2,y2. Ordinary greedy IoU NMS.
    areas = np.prod(np.maximum(boxes[:, 2:] - boxes[:, :2], 0), axis=1)
    order = np.argsort(-scores, kind="stable")
    keep = []
    while order.size:
        i = int(order[0])
        keep.append(i)
        rest = order[1:]
        lo = np.maximum(boxes[i, :2], boxes[rest, :2])
        hi = np.minimum(boxes[i, 2:], boxes[rest, 2:])
        intersection = np.prod(np.maximum(hi - lo, 0), axis=1)
        union = areas[i] + areas[rest] - intersection
        iou = np.divide(intersection, union,
                        out=np.zeros_like(intersection), where=union > 0)
        order = rest[iou <= threshold]
    return keep


def crop_pad(image, box, rotation=False):
    wh = box[1] - box[0]
    shift = np.array([0, 0] if rotation else [0, -0.4])
    box = box + shift * wh
    center = box.mean(axis=0)
    half = (box[1] - box[0]) * (4 if rotation else 3) / 2
    box = np.array([center - half, center + half]).astype(np.int32)
    box[:, 0] = np.clip(box[:, 0], 0, image.shape[1])
    box[:, 1] = np.clip(box[:, 1], 0, image.shape[0])
    crop = image[box[0, 1]:box[1, 1], box[0, 0]:box[1, 0]]
    if not crop.size:
        raise ValueError("Empty hand crop")
    side = int(np.linalg.norm(crop.shape[:2]) if rotation
               else max(crop.shape[:2]))
    ph, pw = side - crop.shape[0], side - crop.shape[1]
    left, top = pw // 2, ph // 2
    crop = cv.copyMakeBorder(
        crop, top, ph - top, left, pw - left,
        cv.BORDER_CONSTANT, value=(0, 0, 0))
    return crop, box, box[0] - [left, top]


def hand_input(image, box, points):
    stage, clipped, bias = crop_pad(image, box.reshape(2, 2), True)
    stage = cv.cvtColor(stage, cv.COLOR_BGR2RGB)
    local = points - bias
    delta = local[2] - local[0]
    radians = np.pi / 2 - np.arctan2(-delta[1], delta[0])
    radians -= 2 * np.pi * np.floor((radians + np.pi) / (2 * np.pi))
    angle = np.rad2deg(radians)
    matrix = cv.getRotationMatrix2D(
        tuple((clipped - bias).mean(axis=0)), angle, 1.0)
    rotated = cv.warpAffine(
        stage, matrix, (stage.shape[1], stage.shape[0]))
    rp = np.c_[local, np.ones(7)] @ matrix.T
    crop, rotated_box, _ = crop_pad(
        rotated, np.array([rp.min(axis=0), rp.max(axis=0)]))
    roi = cv.resize(crop, (224, 224), interpolation=cv.INTER_AREA)
    return roi, rotated_box, angle, matrix, bias


def save_image(path, image):
    if not cv.imwrite(str(path), image):
        raise RuntimeError(f"Could not save {path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--models", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    output = Path(args.out)
    # Each run gets its own directory; don't overwrite earlier results.
    output.mkdir(parents=True, exist_ok=False)
    models = Path(args.models)
    image = cv.imread(args.image)
    if image is None:
        raise ValueError("Could not read input image")
    h, w = image.shape[:2]
    anchors, reference_hash = load_anchors(output)

    ratio = min(192 / h, 192 / w)
    nh, nw = (np.array([h, w]) * ratio).astype(np.int32)
    top, left = int((192 - nh) // 2), int((192 - nw) // 2)
    padded = cv.copyMakeBorder(
        cv.resize(image, (int(nw), int(nh))),
        top, int(192 - nh) - top, left, int(192 - nw) - left,
        cv.BORDER_CONSTANT, value=(0, 0, 0))
    blob = (cv.cvtColor(padded, cv.COLOR_BGR2RGB)
            .astype(np.float32) / 255.0)[None]
    palm_session = session(models / "palm_detection_mediapipe_2023feb.onnx")
    raw, logits = palm_session.run(
        ["Identity", "Identity_1"], {"input_1": blob})
    assert raw.shape == (1, 2016, 18), raw.shape
    assert logits.shape == (1, 2016, 1), logits.shape
    assert np.isfinite(raw).all() and np.isfinite(logits).all()
    np.savez(output / "palm_raw.npz", input=blob, boxes=raw, logits=logits)

    scores = np.exp(-np.logaddexp(
        0.0, -logits[0, :, 0].astype(np.float64)))
    size = np.array([192, 192])
    bias = (np.array([left, top]) / ratio).astype(np.int32)
    center, wh = raw[0, :, :2] / size, raw[0, :, 2:4] / size
    xy1 = (center - wh / 2 + anchors) * max(w, h) - bias
    xy2 = (center + wh / 2 + anchors) * max(w, h) - bias
    boxes = np.c_[xy1, xy2]
    points = (raw[0, :, 4:].reshape(-1, 7, 2) / size
              + anchors[:, None, :]) * max(w, h) - bias
    candidates = np.flatnonzero(
        (scores > 0.3) & np.all(xy2 > xy1, axis=1))
    selected = candidates[nms(boxes[candidates], scores[candidates])]
    print("Palm candidates:", len(candidates))
    print("After NMS:", len(selected))

    hand_session = session(models / "handpose_estimation_mediapipe_2023feb.onnx")
    canvas = image.copy()
    results = []
    chains = [[0,1,2,3,4], [0,5,6,7,8], [5,9,10,11,12],
              [9,13,14,15,16], [13,17,18,19,20], [0,17]]
    for index in selected:
        roi, rotated_box, angle, matrix, pad_bias = hand_input(
            image, boxes[index], points[index])
        hand_blob = (roi.astype(np.float32) / 255.0)[None]
        landmarks, conf, handed, world = hand_session.run(
            ["Identity", "Identity_1", "Identity_2", "Identity_3"],
            {"input_1": hand_blob})
        assert landmarks.shape == (1, 63), landmarks.shape
        assert all(np.isfinite(v).all() for v in (landmarks, conf, handed, world))
        confidence = float(conf.item())
        print(f"Anchor {index}: palm={scores[index]:.6f}, hand={confidence:.6f}")
        save_image(output / f"roi_{index}.png",
                   cv.cvtColor(roi, cv.COLOR_RGB2BGR))
        np.savez(output / f"hand_raw_{index}.npz",
                 input=hand_blob, landmarks=landmarks, confidence=conf,
                 handedness=handed, world=world,
                 rotated_box=rotated_box, angle=angle,
                 rotation_matrix=matrix, pad_bias=pad_bias)
        if confidence < 0.8:
            continue
        # Match reference float32 intermediate operations.
        lm = landmarks.reshape(21, 3).copy()
        scale = max((rotated_box[1] - rotated_box[0]) / np.array([224, 224]))
        lm[:, :2] = (lm[:, :2] - np.array([112, 112])) * scale
        rotation = cv.getRotationMatrix2D((0, 0), angle, 1.0)
        offsets = lm[:, :2] @ rotation[:, :2]
        original_center = cv.invertAffineTransform(matrix) @ np.r_[
            rotated_box.mean(axis=0), 1.0]
        lm[:, :2] = offsets + original_center + pad_bias
        xy = lm[:, :2]
        results.append({
            "anchor_index": int(index), "palm_score": float(scores[index]),
            "hand_confidence": confidence,
            "handedness_raw": float(handed.item()),
            "physical_hand": "unverified",
            "palm_box_xyxy": boxes[index].tolist(),
            "landmarks_xy": xy.tolist(),
        })
        pixels = np.rint(xy).astype(int)
        for chain in chains:
            for a, b in zip(chain, chain[1:]):
                cv.line(canvas, tuple(pixels[a]), tuple(pixels[b]), (0,255,0), 1)
        for i, (x, y) in enumerate(pixels):
            cv.circle(canvas, (int(x), int(y)), 2, (0,0,255), -1)
            cv.putText(canvas, str(i), (int(x)+3, int(y)-3),
                       cv.FONT_HERSHEY_SIMPLEX, 0.3, (0,255,255), 1)

    report = {
        "image_size_wh": [w, h],
        "coordinate_system": "original unflipped image pixels",
        "versions": {"numpy": np.__version__, "opencv": cv.__version__,
                     "onnxruntime": ort.__version__},
        "palm_reference_sha256": reference_hash,
        "nms": "greedy xyxy IoU; threshold 0.3",
        "hands": results,
    }
    (output / "result.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    save_image(output / "overlay.png", canvas)
    print("Accepted hands:", len(results))
    print("Results:", output)


if __name__ == "__main__":
    main()
