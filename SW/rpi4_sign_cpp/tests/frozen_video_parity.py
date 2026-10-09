import importlib.util
import os

import cv2


# ============================================================
# Paths
# ============================================================

BASE_DIR = r"C:\2026ESWContest_smart_mutjaengideul"

FROZEN_PATH = os.path.join(
    BASE_DIR,
    "07g_webcam_15class_final_frozen.py",
)

VIDEO_PATH = os.path.join(
    BASE_DIR,
    "SW",
    "rpi4_sign_cpp",
    "tests",
    "fixtures",
    "real_sign_video",
    "real_sign_01.avi",
)


# ============================================================
# Load frozen 07g WITHOUT modifying it.
# ============================================================

spec = importlib.util.spec_from_file_location(
    "frozen07g_video_parity",
    FROZEN_PATH,
)

if spec is None or spec.loader is None:
    raise RuntimeError(
        "Frozen 07g module spec 생성 실패"
    )

frozen = importlib.util.module_from_spec(
    spec
)

spec.loader.exec_module(
    frozen
)


# ============================================================
# Video capture replacement
#
# This replaces ONLY:
#
#     u.capture_sequence()
#
# The Frozen 07g feature/classification logic remains untouched.
#
# Original 06u semantics reproduced here:
#
#   cv2.flip(frame, 1)
#   BGR -> RGB
#   MediaPipe Hands
#   runtime.extract_hands()
#   append only when LEFT or RIGHT exists
# ============================================================

capture_call_count = 0


def capture_video_sequence():

    global capture_call_count

    capture_call_count += 1


    # --------------------------------------------------------
    # Frozen main() is a loop.
    #
    # First call:
    #     process real_sign_01.avi
    #
    # Second call:
    #     return None
    #     -> frozen main exits normally.
    # --------------------------------------------------------

    if capture_call_count > 1:

        print()
        print(
            "[PARITY] video processing complete"
        )

        return None


    mp_hands = (
        frozen.u.mp.solutions.hands
    )


    hands = mp_hands.Hands(
        static_image_mode=False,
        max_num_hands=2,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )


    cap = cv2.VideoCapture(
        VIDEO_PATH
    )


    if not cap.isOpened():

        hands.close()

        raise RuntimeError(
            "Parity video를 열 수 없습니다: "
            + VIDEO_PATH
        )


    recording_frames = []


    decoded_frames = 0

    detected_frames = 0

    left_frames = 0

    right_frames = 0

    both_frames = 0


    try:

        while True:

            ret, frame = (
                cap.read()
            )


            if not ret:

                break


            decoded_frames += 1


            # ------------------------------------------------
            # EXACT 06u preprocessing
            # ------------------------------------------------

            frame = cv2.flip(
                frame,
                1,
            )


            height, width = (
                frame.shape[:2]
            )


            rgb = cv2.cvtColor(
                frame,
                cv2.COLOR_BGR2RGB,
            )


            results = hands.process(
                rgb
            )


            detected = (
                frozen.u.runtime.extract_hands(
                    results,
                    width,
                    height,
                )
            )


            left_xy = None

            right_xy = None


            if "LEFT" in detected:

                left_xy = (
                    detected[
                        "LEFT"
                    ][
                        "xy"
                    ]
                )


            if "RIGHT" in detected:

                right_xy = (
                    detected[
                        "RIGHT"
                    ][
                        "xy"
                    ]
                )


            # ------------------------------------------------
            # EXACT 06u recording condition
            # ------------------------------------------------

            if (
                left_xy is not None
                or
                right_xy is not None
            ):

                recording_frames.append(
                    (
                        left_xy,
                        right_xy,
                    )
                )


                detected_frames += 1


                if left_xy is not None:

                    left_frames += 1


                if right_xy is not None:

                    right_frames += 1


                if (
                    left_xy is not None
                    and
                    right_xy is not None
                ):

                    both_frames += 1


    finally:

        cap.release()

        hands.close()


    # ========================================================
    # Input parity diagnostics
    # ========================================================

    print()
    print("=" * 80)

    print(
        "FROZEN PYTHON VIDEO PARITY INPUT"
    )

    print("=" * 80)


    print(
        "video           :",
        VIDEO_PATH,
    )


    print(
        "decoded frames  :",
        decoded_frames,
    )


    print(
        "detected frames :",
        detected_frames,
    )


    print(
        "recorded frames :",
        len(
            recording_frames
        ),
    )


    print(
        "left frames     :",
        left_frames,
    )


    print(
        "right frames    :",
        right_frames,
    )


    print(
        "both frames     :",
        both_frames,
    )


    print("=" * 80)


    return recording_frames


# ============================================================
# Replace capture ONLY.
# ============================================================

frozen.u.capture_sequence = (
    capture_video_sequence
)


# ============================================================
# Run the original Frozen 07g main.
#
# Everything after capture_sequence() is original frozen code:
#
# build_webcam_feature()
# validate_webcam_feature()
# C4
# one-hand / two-hand classifier
# TEMP rescue
# final result
# ============================================================

if __name__ == "__main__":

    print()
    print("=" * 80)

    print(
        "FROZEN 07g VIDEO PARITY RUN"
    )

    print("=" * 80)


    frozen.main()