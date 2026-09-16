#include "runtime_data.hpp"

#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>


namespace sign_engine {

namespace {

template <typename T>
std::vector<T> readBinaryFile(
    const std::filesystem::path& path,
    std::size_t expected_count
) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);

    if (!file.is_open()) {
        throw std::runtime_error(
            "Failed to open runtime data file: " + path.string()
        );
    }

    const std::streamsize file_size = file.tellg();

    const std::size_t expected_bytes =
        expected_count * sizeof(T);

    if (file_size < 0 ||
        static_cast<std::size_t>(file_size) != expected_bytes) {

        throw std::runtime_error(
            "Invalid file size: " + path.string() +
            " (expected " + std::to_string(expected_bytes) +
            " bytes, got " + std::to_string(file_size) + " bytes)"
        );
    }

    file.seekg(0, std::ios::beg);

    std::vector<T> data(expected_count);

    if (!file.read(
            reinterpret_cast<char*>(data.data()),
            static_cast<std::streamsize>(expected_bytes))) {

        throw std::runtime_error(
            "Failed to read runtime data file: " + path.string()
        );
    }

    return data;
}

}  // namespace


RuntimeData loadRuntimeData(
    const std::string& runtime_data_dir
) {
    const std::filesystem::path base(runtime_data_dir);

    RuntimeData data;

    data.twohand_local = readBinaryFile<float>(
        base / "twohand_local.bin",
        TWOHAND_REFERENCE_COUNT *
        TARGET_FRAMES *
        LOCAL_FEATURE_DIM
    );

    data.twohand_class_ids = readBinaryFile<std::int32_t>(
        base / "twohand_class_ids.bin",
        TWOHAND_REFERENCE_COUNT
    );

    data.onehand_local = readBinaryFile<float>(
        base / "onehand_local.bin",
        ONEHAND_REFERENCE_COUNT *
        TARGET_FRAMES *
        LOCAL_FEATURE_DIM
    );

    data.onehand_class_ids = readBinaryFile<std::int32_t>(
        base / "onehand_class_ids.bin",
        ONEHAND_REFERENCE_COUNT
    );

    data.c4_mean = readBinaryFile<float>(
        base / "c4_mean.bin",
        C4_FEATURE_DIM
    );

    data.c4_std = readBinaryFile<float>(
        base / "c4_std.bin",
        C4_FEATURE_DIM
    );

    data.c4_sign = readBinaryFile<float>(
        base / "c4_sign.bin",
        C4_SIGN_REFERENCE_COUNT *
        C4_FEATURE_DIM
    );

    data.c4_nosign = readBinaryFile<float>(
        base / "c4_nosign.bin",
        C4_NOSIGN_REFERENCE_COUNT *
        C4_FEATURE_DIM
    );

    validateRuntimeData(data);

    return data;
}


void validateRuntimeData(
    const RuntimeData& data
) {
    if (data.twohand_local.size() !=
        TWOHAND_REFERENCE_COUNT *
        TARGET_FRAMES *
        LOCAL_FEATURE_DIM) {

        throw std::runtime_error(
            "Invalid twohand_local data size"
        );
    }

    if (data.twohand_class_ids.size() !=
        TWOHAND_REFERENCE_COUNT) {

        throw std::runtime_error(
            "Invalid twohand_class_ids data size"
        );
    }

    if (data.onehand_local.size() !=
        ONEHAND_REFERENCE_COUNT *
        TARGET_FRAMES *
        LOCAL_FEATURE_DIM) {

        throw std::runtime_error(
            "Invalid onehand_local data size"
        );
    }

    if (data.onehand_class_ids.size() !=
        ONEHAND_REFERENCE_COUNT) {

        throw std::runtime_error(
            "Invalid onehand_class_ids data size"
        );
    }

    if (data.c4_mean.size() != C4_FEATURE_DIM) {
        throw std::runtime_error(
            "Invalid c4_mean data size"
        );
    }

    if (data.c4_std.size() != C4_FEATURE_DIM) {
        throw std::runtime_error(
            "Invalid c4_std data size"
        );
    }

    if (data.c4_sign.size() !=
        C4_SIGN_REFERENCE_COUNT *
        C4_FEATURE_DIM) {

        throw std::runtime_error(
            "Invalid c4_sign data size"
        );
    }

    if (data.c4_nosign.size() !=
        C4_NOSIGN_REFERENCE_COUNT *
        C4_FEATURE_DIM) {

        throw std::runtime_error(
            "Invalid c4_nosign data size"
        );
    }
}

}  // namespace sign_engine