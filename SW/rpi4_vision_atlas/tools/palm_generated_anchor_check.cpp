#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

template<class T>
std::vector<T> read_bin(const fs::path& path) {
    const auto bytes = fs::file_size(path);
    if (bytes % sizeof(T))
        throw std::runtime_error("Invalid byte count: " + path.string());
    std::vector<T> data(bytes / sizeof(T));
    std::ifstream file(path, std::ios::binary);
    if (!file)
        throw std::runtime_error("Cannot open: " + path.string());
    if (bytes && !file.read(reinterpret_cast<char*>(data.data()),
                            static_cast<std::streamsize>(bytes)))
        throw std::runtime_error("Read failed: " + path.string());
    return data;
}

template<class T>
void check_size(const std::vector<T>& data, size_t count) {
    if (data.size() != count)
        throw std::runtime_error("Unexpected tensor size");
    for (auto x : data)
        if (!std::isfinite(static_cast<double>(x)))
            throw std::runtime_error("Non-finite input");
}

double max_error(const std::vector<double>& actual,
                 const std::vector<double>& expected) {
    if (actual.size() != expected.size())
        throw std::runtime_error("Comparison size mismatch");
    double error = 0;
    for (size_t i = 0; i < actual.size(); ++i) {
        if (!std::isfinite(actual[i]) || !std::isfinite(expected[i]))
            throw std::runtime_error("Non-finite comparison");
        error = std::max(error, std::abs(actual[i] - expected[i]));
    }
    return error;
}

double sigmoid(double x) {
    if (x >= 0) return 1.0 / (1.0 + std::exp(-x));
    const double e = std::exp(x);
    return e / (1.0 + e);
}

double iou(const std::vector<double>& boxes, int a, int b) {
    const double* x = &boxes[4 * a];
    const double* y = &boxes[4 * b];
    const double iw = std::max(0.0, std::min(x[2], y[2]) - std::max(x[0], y[0]));
    const double ih = std::max(0.0, std::min(x[3], y[3]) - std::max(x[1], y[1]));
    const double intersection = iw * ih;
    const double area_x = (x[2] - x[0]) * (x[3] - x[1]);
    const double area_y = (y[2] - y[0]) * (y[3] - y[1]);
    const double union_area = area_x + area_y - intersection;
    return union_area > 0 ? intersection / union_area : 0;
}

int main(int argc, char** argv) {
    try {
        if (argc != 4)
            throw std::runtime_error(
                "Usage: palm_decode_check <fixture_dir> <width> <height>");
        static_assert(sizeof(float) == 4 && sizeof(double) == 8);
        const uint16_t endian = 1;
        if (*reinterpret_cast<const unsigned char*>(&endian) != 1)
            throw std::runtime_error("Little-endian host required");

        const fs::path dir = argv[1];
        const int w = std::stoi(argv[2]), h = std::stoi(argv[3]);
        if (w <= 0 || h <= 0)
            throw std::runtime_error("Invalid image dimensions");
        constexpr size_t count = 2016;
        const auto raw = read_bin<float>(dir / "raw_boxes_f32.bin");
        const auto logits = read_bin<float>(dir / "raw_logits_f32.bin");
        
std::vector<double> anchors;
anchors.reserve(count * 2);
for (const auto& config :
     std::array<std::array<int, 2>, 2>{{{24, 2}, {12, 6}}}) {
    const int grid = config[0];
    const int repeats = config[1];
    for (int y = 0; y < grid; ++y)
        for (int x = 0; x < grid; ++x)
            for (int repeat = 0; repeat < repeats; ++repeat) {
                anchors.push_back((x + 0.5) / grid);
                anchors.push_back((y + 0.5) / grid);
            }
}

        const auto expected_boxes = read_bin<double>(dir / "expected_boxes_f64.bin");
        const auto expected_points = read_bin<double>(dir / "expected_points_f64.bin");
        const auto expected_scores = read_bin<double>(dir / "expected_scores_f64.bin");
        const auto expected_keep = read_bin<int32_t>(dir / "expected_keep_i32.bin");
        check_size(raw, count * 18);
        check_size(logits, count);
        check_size(anchors, count * 2);
        check_size(expected_boxes, count * 4);
        check_size(expected_points, count * 14);
        check_size(expected_scores, count);

        // Match the Python reference's resize and integer padding bias.
        const double ratio = std::min(192.0 / h, 192.0 / w);
        const int nh = static_cast<int>(h * ratio);
        const int nw = static_cast<int>(w * ratio);
        const std::array<double, 2> bias = {
            static_cast<double>(static_cast<int>(((192 - nw) / 2) / ratio)),
            static_cast<double>(static_cast<int>(((192 - nh) / 2) / ratio))
        };
        const double scale = std::max(w, h);
        std::vector<double> boxes(count * 4), points(count * 14), scores(count);

        for (size_t i = 0; i < count; ++i) {
            scores[i] = sigmoid(static_cast<double>(logits[i]));
            for (size_t d = 0; d < 2; ++d) {
                const double center = static_cast<double>(raw[i * 18 + d]) / 192.0;
                const double size = static_cast<double>(raw[i * 18 + 2 + d]) / 192.0;
                const double anchor = anchors[i * 2 + d];
                boxes[i * 4 + d] =
                    (center - size / 2.0 + anchor) * scale - bias[d];
                boxes[i * 4 + 2 + d] =
                    (center + size / 2.0 + anchor) * scale - bias[d];
                for (size_t k = 0; k < 7; ++k)
                    points[i * 14 + k * 2 + d] =
                        (static_cast<double>(raw[i * 18 + 4 + k * 2 + d])
                         / 192.0 + anchor) * scale - bias[d];
            }
        }

        std::vector<int> order;
        for (size_t i = 0; i < count; ++i)
            if (scores[i] > 0.3 &&
                boxes[4*i+2] > boxes[4*i] &&
                boxes[4*i+3] > boxes[4*i+1])
                order.push_back(static_cast<int>(i));
        const auto candidate_count = order.size();
        std::stable_sort(order.begin(), order.end(),
            [&](int a, int b) { return scores[a] > scores[b]; });

        std::vector<int32_t> keep;
        while (!order.empty()) {
            const int best = order.front();
            keep.push_back(best);
            std::vector<int> remaining;
            for (size_t j = 1; j < order.size(); ++j)
                if (iou(boxes, best, order[j]) <= 0.3)
                    remaining.push_back(order[j]);
            order.swap(remaining);
        }

        const double box_error = max_error(boxes, expected_boxes);
        const double point_error = max_error(points, expected_points);
        const double score_error = max_error(scores, expected_scores);
        const bool nms_ok = keep == expected_keep;
        const bool pass = box_error <= 1e-4 && point_error <= 1e-4
                       && score_error <= 1e-12 && nms_ok;

        std::cout << std::scientific << std::setprecision(12);
        std::cout << "Box max_abs_error: " << box_error << "\n";
        std::cout << "Keypoint max_abs_error: " << point_error << "\n";
        std::cout << "Score max_abs_error: " << score_error << "\n";
        std::cout << "Candidates: " << candidate_count << "\n";
        std::cout << "Kept IDs:";
        for (auto id : keep) std::cout << " " << id;
        std::cout << "\nNMS exact match: " << (nms_ok ? "YES" : "NO")
                  << "\n" << (pass ? "PASS" : "FAIL") << "\n";
        return pass ? 0 : 1;
    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }
}
