#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace fs = std::filesystem;

template<class T>
std::vector<T> read(const fs::path& path, size_t count) {
    if (fs::file_size(path) != count*sizeof(T))
        throw std::runtime_error("Wrong file size: " + path.string());
    std::vector<T> data(count);
    std::ifstream file(path, std::ios::binary);
    if (!file.read(reinterpret_cast<char*>(data.data()), count*sizeof(T)))
        throw std::runtime_error("Read failed: " + path.string());
    for (auto x : data)
        if (!std::isfinite(static_cast<double>(x)))
            throw std::runtime_error("Non-finite input");
    return data;
}

int main(int argc, char** argv) {
    try {
        if (argc != 2)
            throw std::runtime_error("Usage: hand_restore_check <fixture>");
        static_assert(sizeof(float)==4 && sizeof(double)==8);
        const uint16_t endian=1;
        if (*reinterpret_cast<const unsigned char*>(&endian)!=1)
            throw std::runtime_error("Little-endian host required");

        const fs::path dir=argv[1];
        const auto raw=read<float>(dir/"hand_landmarks_f32.bin",63);
        const auto expected=read<float>(dir/"expected_original_xy_f32.bin",42);
        const auto box=read<int32_t>(dir/"expected_rotated_box_i32.bin",4);
        const auto bias=read<int32_t>(dir/"expected_bias_i32.bin",2);
        auto matrix_data=read<double>(dir/"expected_matrix_f64.bin",6);
        const auto angle=read<double>(dir/"expected_angle_f64.bin",1);

        const double scale=std::max(
            (double(box[2])-box[0])/224.0,
            (double(box[3])-box[1])/224.0);
        if (scale<=0) throw std::runtime_error("Invalid ROI size");

        cv::Mat matrix(2,3,CV_64F,matrix_data.data());
        cv::Mat inverse;
        cv::invertAffineTransform(matrix,inverse);
        const cv::Mat rotation=cv::getRotationMatrix2D(
            cv::Point2f(0,0),angle[0],1.0);

        const double cx=(double(box[0])+box[2])/2.0;
        const double cy=(double(box[1])+box[3])/2.0;
        const double original_cx=inverse.at<double>(0,0)*cx
                               + inverse.at<double>(0,1)*cy
                               + inverse.at<double>(0,2);
        const double original_cy=inverse.at<double>(1,0)*cx
                               + inverse.at<double>(1,1)*cy
                               + inverse.at<double>(1,2);

        std::vector<float> actual(42);
        double max_abs=0,max_distance=0,sum_distance=0;
        int worst=-1;
        for (int i=0;i<21;++i) {
            // Match NumPy's float64 expression -> float32 assignment.
            const float x=static_cast<float>((double(raw[3*i])-112.0)*scale);
            const float y=static_cast<float>((double(raw[3*i+1])-112.0)*scale);

            // Row-vector multiplication, as in the Python reference.
            const double ox=double(x)*rotation.at<double>(0,0)
                           + double(y)*rotation.at<double>(1,0);
            const double oy=double(x)*rotation.at<double>(0,1)
                           + double(y)*rotation.at<double>(1,1);
            actual[2*i]=static_cast<float>((ox+original_cx)+bias[0]);
            actual[2*i+1]=static_cast<float>((oy+original_cy)+bias[1]);
            if (!std::isfinite(actual[2*i]) || !std::isfinite(actual[2*i+1]))
                throw std::runtime_error("Non-finite output");

            const double dx=double(actual[2*i])-expected[2*i];
            const double dy=double(actual[2*i+1])-expected[2*i+1];
            max_abs=std::max({max_abs,std::abs(dx),std::abs(dy)});
            const double distance=std::hypot(dx,dy);
            sum_distance+=distance;
            if (worst<0 || distance>max_distance) {
                max_distance=distance;
                worst=i;
            }
        }

        std::ofstream file(dir/"actual_original_xy_f32.bin",std::ios::binary);
        file.write(reinterpret_cast<const char*>(actual.data()),
                   actual.size()*sizeof(float));
        file.close();
        if (!file) throw std::runtime_error("Output write failed");

        // Numerical parity check; not an application accuracy threshold.
        const bool pass=max_abs<=1e-5;
        std::cout << std::setprecision(12)
                  << "XY max_abs_error: " << max_abs << "\n"
                  << "Max point distance: " << max_distance << "\n"
                  << "Mean point distance: " << sum_distance/21 << "\n"
                  << "Worst landmark ID: " << worst << "\n"
                  << "Python XY: " << expected[2*worst] << " "
                  << expected[2*worst+1] << "\n"
                  << "C++ XY: " << actual[2*worst] << " "
                  << actual[2*worst+1] << "\n"
                  << (pass?"PASS":"FAIL") << "\n";
        return pass?0:1;
    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }
}
