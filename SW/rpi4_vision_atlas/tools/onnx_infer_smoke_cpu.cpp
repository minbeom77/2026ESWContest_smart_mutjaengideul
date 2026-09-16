#include <algorithm>
#include <iostream>
#include <memory>
#include <numeric>
#include <string>
#include <unordered_map>
#include <vector>

#include <onnxruntime_cxx_api.h>

static void PrintShape(const std::vector<int64_t>& shape) {
    std::cout << "[";
    for (size_t i = 0; i < shape.size(); ++i) {
        std::cout << shape[i];
        if (i + 1 < shape.size()) {
            std::cout << ", ";
        }
    }
    std::cout << "]";
}

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <model.onnx>\n";
        return 1;
    }

    try {
        const std::string model_path = argv[1];

        Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "onnx_infer_smoke");

        Ort::SessionOptions options;
        options.SetGraphOptimizationLevel(
            GraphOptimizationLevel::ORT_ENABLE_ALL);
        options.SetIntraOpNumThreads(1);
        options.SetInterOpNumThreads(1);

        // Raspberry Pi 4 CPU inference

        std::cout << "Loading model: " << model_path << "\n";

        Ort::Session session(env, model_path.c_str(), options);
        Ort::AllocatorWithDefaultOptions allocator;

        const size_t input_count = session.GetInputCount();
        const size_t output_count = session.GetOutputCount();

        if (input_count != 1) {
            std::cerr << "Expected exactly 1 input, got "
                      << input_count << "\n";
            return 1;
        }

        // Input information
        auto input_name_alloc =
            session.GetInputNameAllocated(0, allocator);
        std::string input_name = input_name_alloc.get();

        auto input_type_info = session.GetInputTypeInfo(0);
        auto input_tensor_info =
            input_type_info.GetTensorTypeAndShapeInfo();

        if (input_tensor_info.GetElementType() !=
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
            std::cerr << "Input is not float32\n";
            return 1;
        }

        std::vector<int64_t> input_shape =
            input_tensor_info.GetShape();

        for (auto& dim : input_shape) {
            if (dim < 0) {
                dim = 1;
            }
        }

        size_t input_elements = 1;
        for (const auto dim : input_shape) {
            input_elements *= static_cast<size_t>(dim);
        }

        std::cout << "Input name: " << input_name << "\n";
        std::cout << "Input shape: ";
        PrintShape(input_shape);
        std::cout << "\n";
        std::cout << "Input elements: "
                  << input_elements << "\n";

        // Dummy normalized image: every pixel = 0.5
        std::vector<float> input_data(input_elements, 0.5f);

        Ort::MemoryInfo memory_info =
            Ort::MemoryInfo::CreateCpu(
                OrtArenaAllocator,
                OrtMemTypeDefault);

        Ort::Value input_tensor =
            Ort::Value::CreateTensor<float>(
                memory_info,
                input_data.data(),
                input_data.size(),
                input_shape.data(),
                input_shape.size());

        // Output names
        std::vector<std::string> output_name_strings;
        std::vector<const char*> output_names;

        for (size_t i = 0; i < output_count; ++i) {
            auto name =
                session.GetOutputNameAllocated(i, allocator);
            output_name_strings.emplace_back(name.get());
        }

        for (const auto& name : output_name_strings) {
            output_names.push_back(name.c_str());
        }

        const char* input_names[] = {
            input_name.c_str()
        };

        std::cout << "\nRunning inference with CPU...\n";

        auto outputs = session.Run(
            Ort::RunOptions{nullptr},
            input_names,
            &input_tensor,
            1,
            output_names.data(),
            output_names.size());

        std::cout << "INFERENCE SUCCESS\n";
        std::cout << "Outputs: "
                  << outputs.size() << "\n\n";

        for (size_t i = 0; i < outputs.size(); ++i) {
            if (!outputs[i].IsTensor()) {
                std::cout << "OUTPUT " << i
                          << " is not a tensor\n";
                continue;
            }

            auto info =
                outputs[i].GetTensorTypeAndShapeInfo();

            auto shape = info.GetShape();
            const size_t count =
                info.GetElementCount();

            std::cout << "OUTPUT " << i
                      << " (" << output_name_strings[i] << ")\n";

            std::cout << "  shape: ";
            PrintShape(shape);
            std::cout << "\n";

            std::cout << "  elements: "
                      << count << "\n";

            if (info.GetElementType() ==
                ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {

                const float* data =
                    outputs[i].GetTensorData<float>();

                const size_t preview =
                    std::min<size_t>(8, count);

                std::cout << "  first values: ";

                for (size_t j = 0; j < preview; ++j) {
                    std::cout << data[j];

                    if (j + 1 < preview) {
                        std::cout << ", ";
                    }
                }

                std::cout << "\n";
            }

            std::cout << "\n";
        }

        return 0;
    }
    catch (const Ort::Exception& e) {
        std::cerr << "ONNX Runtime ERROR: "
                  << e.what() << "\n";
        return 1;
    }
    catch (const std::exception& e) {
        std::cerr << "ERROR: "
                  << e.what() << "\n";
        return 1;
    }
}
