#include "jsonl_frame_hands.hpp"
#include "runtime_data.hpp"
#include "sign_runtime.hpp"

#include <cstdlib>
#include <exception>
#include <iomanip>
#include <iostream>
#include <string>

int main(
    int argc,
    char* argv[]
) {
    if (argc != 3) {
        std::cerr
            << "Usage:\n"
            << "  jsonl_classifier_parity "
            << "<input.jsonl> <runtime_data_dir>\n";

        return EXIT_FAILURE;
    }

    const std::string jsonl_path =
        argv[1];

    const std::string runtime_dir =
        argv[2];

    try {
        // ----------------------------------------------------
        // Exact teammate JSON/JSONL -> RecordingFrames adapter.
        // ----------------------------------------------------

        const sign_engine::JsonlRecordingResult recording =
            sign_engine::loadRecordingFramesFromJson(
                {jsonl_path}
            );

        // ----------------------------------------------------
        // Exact production runtime-data loading path.
        // ----------------------------------------------------

        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_dir
            );

        sign_engine::validateRuntimeData(
            runtime
        );

        // ----------------------------------------------------
        // Exact production classifier.
        // ----------------------------------------------------

        const sign_engine::SignRecognitionResult result =
            sign_engine::classifyRecording(
                recording.frames,
                runtime
            );

        std::cout
            << std::fixed
            << std::setprecision(6);

        std::cout
            << "========================================\n"
            << "JSONL CLASSIFIER PARITY RESULT\n"
            << "========================================\n";

        std::cout
            << "json_documents  : "
            << recording.document_count
            << '\n';

        std::cout
            << "adapter_frames  : "
            << recording.frames.size()
            << '\n';

        std::cout
            << "maximum_hands   : "
            << recording.maximum_hands_per_frame
            << '\n';

        std::cout
            << "single_stabilize: "
            << (
                recording.used_single_hand_stabilization
                    ? "true"
                    : "false"
            )
            << '\n';

        if (recording.has_median_handedness) {
            std::cout
                << "median_raw      : "
                << recording.median_handedness_raw
                << '\n';

            std::cout
                << "stabilized_hand : "
                << recording.stabilized_physical_hand
                << '\n';
        }

        std::cout
            << '\n'
            << "valid           : "
            << (result.valid ? "true" : "false")
            << '\n';

        std::cout
            << "final_id        : "
            << result.final_id
            << '\n';

        std::cout
            << "stage           : "
            << result.stage
            << '\n';

        std::cout
            << "is_nosign       : "
            << (result.is_nosign ? "true" : "false")
            << '\n';

        std::cout
            << "source_mode     : "
            << result.source_mode
            << '\n';

        std::cout
            << "selected_frames : "
            << result.selected_frames
            << '\n';

        std::cout
            << "total_frames    : "
            << result.recording_stats.total_frames
            << '\n';

        std::cout
            << "left_frames     : "
            << result.recording_stats.left_count
            << '\n';

        std::cout
            << "right_frames    : "
            << result.recording_stats.right_count
            << '\n';

        std::cout
            << "both_frames     : "
            << result.recording_stats.both_count
            << '\n';

        std::cout
            << "both_ratio      : "
            << result.recording_stats.both_ratio
            << '\n';

        std::cout
            << "error           : "
            << result.error
            << '\n';

        std::cout
            << "========================================\n";

        if (
            result.valid &&
            result.is_nosign &&
            result.stage ==
                "ONEHAND_C4_NOSIGN_REJECT"
        ) {
            std::cout
                << "EXPECTED PYTHON RESULT MATCH\n";
        } else {
            std::cout
                << "EXPECTED PYTHON RESULT MISMATCH\n";
        }

        return EXIT_SUCCESS;
    }
    catch (const std::exception& error) {
        std::cerr
            << "JSONL CLASSIFIER PARITY FAIL\n"
            << error.what()
            << '\n';

        return EXIT_FAILURE;
    }
}