import importlib.util
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parent

FROZEN_PATH = (
    ROOT
    / "07g_webcam_15class_final_frozen.py"
)

NEW5_PATH = (
    ROOT
    / "new5_reference_v3"
    / "new5_train_v3_80f.npz"
)

OUTPUT_DIR = (
    ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "tests"
    / "fixtures"
    / "temp_positive_real01"
)


TARGET_NPZ_INDEX = 12
TARGET_CLASS_ID = 12


def load_frozen_module():
    spec = importlib.util.spec_from_file_location(
        "frozen_07g",
        FROZEN_PATH,
    )

    if (
        spec is None
        or
        spec.loader is None
    ):
        raise RuntimeError(
            "07g frozen module load spec 생성 실패"
        )

    module = importlib.util.module_from_spec(
        spec
    )

    spec.loader.exec_module(
        module
    )

    return module


def main():
    frozen = load_frozen_module()

    aihub = (
        frozen.load_aihub_train_references()
    )

    with np.load(
        NEW5_PATH,
        allow_pickle=True,
    ) as data:

        features = np.asarray(
            data["features"],
            dtype=np.float32,
        )

        class_ids = np.asarray(
            data["class_ids"],
            dtype=np.int64,
        )

        real_ids = np.asarray(
            data["real_ids"]
        )

        source_paths = np.asarray(
            data["source_paths"]
        )

        index = TARGET_NPZ_INDEX

        actual_class_id = int(
            class_ids[index]
        )

        if (
            actual_class_id
            !=
            TARGET_CLASS_ID
        ):
            raise RuntimeError(
                f"index {index}: "
                f"class_id={actual_class_id}, "
                f"expected={TARGET_CLASS_ID}"
            )

        feature172 = np.ascontiguousarray(
            features[index],
            dtype=np.float32,
        )

        if (
            feature172.shape
            !=
            (80, 172)
        ):
            raise RuntimeError(
                f"Unexpected Feature V3 shape: "
                f"{feature172.shape}"
            )

        local84 = np.ascontiguousarray(
            feature172[
                :,
                0:frozen.LOCAL_DIM,
            ],
            dtype=np.float32,
        )

        if (
            local84.shape
            !=
            (80, 84)
        ):
            raise RuntimeError(
                f"Unexpected Local84 shape: "
                f"{local84.shape}"
            )

        result = frozen.classify_two_hand(
            local=local84,
            aihub=aihub,
        )

        base_id = int(
            result["base_id"]
        )

        final_id = int(
            result["final_id"]
        )

        stage = str(
            result["stage"]
        )

        ranking = result[
            "base_ranking"
        ]

        ranking_class_ids = np.asarray(
            [
                int(item["class_id"])
                for item in ranking
            ],
            dtype=np.int32,
        )

        ranking_scores = np.asarray(
            [
                float(item["score"])
                for item in ranking
            ],
            dtype=np.float32,
        )

        if (
            len(ranking_scores)
            < 2
        ):
            raise RuntimeError(
                "Base ranking has fewer than 2 classes"
            )

        base_margin = np.float32(
            ranking_scores[1]
            -
            ranking_scores[0]
        )

        OUTPUT_DIR.mkdir(
            parents=True,
            exist_ok=True,
        )

        local84.tofile(
            OUTPUT_DIR
            / "input_local84_80x84.bin"
        )

        ranking_class_ids.tofile(
            OUTPUT_DIR
            / "expected_base_ranking_class_ids.bin"
        )

        ranking_scores.tofile(
            OUTPUT_DIR
            / "expected_base_ranking_scores.bin"
        )

        np.asarray(
            [base_id],
            dtype=np.int32,
        ).tofile(
            OUTPUT_DIR
            / "expected_base_id.bin"
        )

        np.asarray(
            [final_id],
            dtype=np.int32,
        ).tofile(
            OUTPUT_DIR
            / "expected_final_id.bin"
        )

        np.asarray(
            [base_margin],
            dtype=np.float32,
        ).tofile(
            OUTPUT_DIR
            / "expected_base_margin.bin"
        )

        (
            OUTPUT_DIR
            / "expected_stage.txt"
        ).write_text(
            stage,
            encoding="utf-8",
        )

        (
            OUTPUT_DIR
            / "fixture_info.txt"
        ).write_text(
            "\n".join(
                [
                    f"npz_index={index}",
                    f"real_id={real_ids[index]}",
                    f"class_id={actual_class_id}",
                    f"source_path={source_paths[index]}",
                    "source=new5_train_v3_80f.npz",
                    "python=frozen_07g",
                ]
            ),
            encoding="utf-8",
        )

        print()
        print(
            "=" * 80
        )
        print(
            "TEMP POSITIVE FIXTURE EXPORT"
        )
        print(
            "=" * 80
        )

        print(
            "NPZ index      :",
            index,
        )

        print(
            "REAL ID        :",
            real_ids[index],
        )

        print(
            "class_id       :",
            actual_class_id,
        )

        print(
            "Local84 shape  :",
            local84.shape,
        )

        print(
            "base_id        :",
            base_id,
        )

        print(
            "final_id       :",
            final_id,
        )

        print(
            "stage          :",
            stage,
        )

        print(
            "base_margin    :",
            f"{float(base_margin):.9f}",
        )

        print()
        print(
            "BASE RANKING"
        )

        for rank_index, (
            class_id,
            score,
        ) in enumerate(
            zip(
                ranking_class_ids,
                ranking_scores,
            ),
            start=1,
        ):
            print(
                f"  {rank_index}. "
                f"class {int(class_id)} "
                f"| score {float(score):.9f}"
            )

        print()
        print(
            "Output:",
            OUTPUT_DIR,
        )

        print()
        print(
            "TEMP POSITIVE FIXTURE EXPORT PASS"
        )
        print(
            "=" * 80
        )


if __name__ == "__main__":
    main()