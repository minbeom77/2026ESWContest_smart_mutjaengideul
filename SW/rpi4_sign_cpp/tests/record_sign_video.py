import cv2
from pathlib import Path


CAMERA_INDEX = 0

OUTPUT_DIR = Path(
    r"C:\2026ESWContest_smart_mutjaengideul"
    r"\SW\rpi4_sign_cpp\tests\fixtures\real_sign_video"
)

OUTPUT_PATH = OUTPUT_DIR / "real_sign_01.avi"


def main():
    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    cap = cv2.VideoCapture(
        CAMERA_INDEX
    )

    if not cap.isOpened():
        raise RuntimeError(
            f"카메라를 열 수 없습니다: index={CAMERA_INDEX}"
        )

    width = int(
        cap.get(
            cv2.CAP_PROP_FRAME_WIDTH
        )
    )

    height = int(
        cap.get(
            cv2.CAP_PROP_FRAME_HEIGHT
        )
    )

    fps = cap.get(
        cv2.CAP_PROP_FPS
    )

    if fps <= 1.0:
        fps = 30.0

    writer = cv2.VideoWriter(
        str(OUTPUT_PATH),
        cv2.VideoWriter_fourcc(
            *"MJPG"
        ),
        fps,
        (width, height),
    )

    if not writer.isOpened():
        cap.release()

        raise RuntimeError(
            "VideoWriter를 열 수 없습니다."
        )

    recording = False
    recorded_frames = 0

    print("카메라 준비 완료")
    print("R : 녹화 시작")
    print("S : 녹화 종료 및 저장")
    print("Q : 종료")

    while True:
        ok, frame = cap.read()

        if not ok:
            print("카메라 frame 읽기 실패")
            break

        display = frame.copy()

        if recording:
            writer.write(frame)
            recorded_frames += 1

            cv2.putText(
                display,
                f"REC {recorded_frames}",
                (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX,
                1.0,
                (0, 0, 255),
                2,
            )
        else:
            cv2.putText(
                display,
                "Press R to record",
                (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX,
                1.0,
                (0, 255, 0),
                2,
            )

        cv2.imshow(
            "Raw Sign Video Recorder",
            display,
        )

        key = (
            cv2.waitKey(1)
            & 0xFF
        )

        if key in (
            ord("r"),
            ord("R"),
        ):
            if not recording:
                recording = True

                print(
                    "RECORDING START"
                )

        elif key in (
            ord("s"),
            ord("S"),
        ):
            if recording:
                print(
                    "RECORDING STOP"
                )

                break

        elif key in (
            ord("q"),
            ord("Q"),
        ):
            break

    writer.release()
    cap.release()
    cv2.destroyAllWindows()

    print()
    print(
        "saved:",
        OUTPUT_PATH,
    )

    print(
        "recorded frames:",
        recorded_frames,
    )

    print(
        "size:",
        width,
        "x",
        height,
    )

    print(
        "fps:",
        fps,
    )


if __name__ == "__main__":
    main()