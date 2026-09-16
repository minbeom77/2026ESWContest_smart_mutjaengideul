#include "runtime_data.hpp"

#include <iostream>
#include <string>


int main() {
    try {
        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";

        const sign_engine::RuntimeData data =
            sign_engine::loadRuntimeData(runtime_dir);

        std::cout << "Runtime data load PASS\n";

        std::cout << "twohand_local: "
                  << data.twohand_local.size()
                  << '\n';

        std::cout << "twohand_class_ids: "
                  << data.twohand_class_ids.size()
                  << '\n';

        std::cout << "onehand_local: "
                  << data.onehand_local.size()
                  << '\n';

        std::cout << "onehand_class_ids: "
                  << data.onehand_class_ids.size()
                  << '\n';

        std::cout << "c4_mean: "
                  << data.c4_mean.size()
                  << '\n';

        std::cout << "c4_std: "
                  << data.c4_std.size()
                  << '\n';

        std::cout << "c4_sign: "
                  << data.c4_sign.size()
                  << '\n';

        std::cout << "c4_nosign: "
                  << data.c4_nosign.size()
                  << '\n';

        return 0;
    }
    catch (const std::exception& e) {
        std::cerr << "Runtime data load FAIL\n";
        std::cerr << e.what() << '\n';

        return 1;
    }
}