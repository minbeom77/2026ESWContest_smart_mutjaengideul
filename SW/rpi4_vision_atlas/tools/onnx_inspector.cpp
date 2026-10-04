#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <onnxruntime_cxx_api.h>

void print_shape(const std::vector<int64_t>& shape) {
    std::cout << "[";
    for (size_t i = 0; i < shape.size(); ++i) {
        std::cout << shape[i];
        if (i + 1 < shape.size()) std::cout << ", ";
    }
    std::cout << "]";
}

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <model.onnx>\n";
        return 1;
    }

    try {
        Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "onnx_inspector");
        Ort::SessionOptions options;
        options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

        Ort::Session session(env, argv[1], options);
        Ort::AllocatorWithDefaultOptions allocator;

        std::cout << "MODEL LOADED OK\n";

        size_t input_count = session.GetInputCount();
        size_t output_count = session.GetOutputCount();

        std::cout << "Inputs: " << input_count << "\n";

        for (size_t i = 0; i < input_count; ++i) {
            auto name = session.GetInputNameAllocated(i, allocator);
            auto type_info = session.GetInputTypeInfo(i);
            auto tensor_info = type_info.GetTensorTypeAndShapeInfo();

            std::cout << "INPUT " << i << "\n";
            std::cout << "  name: " << name.get() << "\n";
            std::cout << "  type: " << tensor_info.GetElementType() << "\n";
            std::cout << "  shape: ";
            print_shape(tensor_info.GetShape());
            std::cout << "\n";
        }

        std::cout << "Outputs: " << output_count << "\n";

        for (size_t i = 0; i < output_count; ++i) {
            auto name = session.GetOutputNameAllocated(i, allocator);
            auto type_info = session.GetOutputTypeInfo(i);
            auto tensor_info = type_info.GetTensorTypeAndShapeInfo();

            std::cout << "OUTPUT " << i << "\n";
            std::cout << "  name: " << name.get() << "\n";
            std::cout << "  type: " << tensor_info.GetElementType() << "\n";
            std::cout << "  shape: ";
            print_shape(tensor_info.GetShape());
            std::cout << "\n";
        }

        return 0;
    }
    catch (const Ort::Exception& e) {
        std::cerr << "ORT ERROR: " << e.what() << "\n";
        return 1;
    }
}
