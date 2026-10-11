#include "InpaintingTools.h"
#include <onnxruntime_c_api.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
struct ModelSession {
    void *library = nullptr;
    const OrtApi *api = nullptr;
    OrtEnv *env = nullptr;
    OrtSession *session = nullptr;
    std::string path;
    void check(OrtStatus *status) const {
        if (!status) return;
        std::string message = api->GetErrorMessage(status);
        api->ReleaseStatus(status);
        throw std::runtime_error(message);
    }
    ~ModelSession() {
        if (session) api->ReleaseSession(session);
        if (env) api->ReleaseEnv(env);
        // Runtime worker/TLS state can outlive a session; retain the loaded image.
    }
    ModelSession(const char *model, const char *runtime) : path(model) {
        library = dlopen(runtime, RTLD_NOW | RTLD_LOCAL);
        if (!library) throw std::runtime_error("Cannot load the bundled inference runtime");
        auto getBase = reinterpret_cast<const OrtApiBase *(ORT_API_CALL *)(void)>(dlsym(library, "OrtGetApiBase"));
        if (!getBase || !(api = getBase()->GetApi(ORT_API_VERSION)))
            throw std::runtime_error("Incompatible inference runtime");
        try {
            check(api->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "ImageProInpainting", &env));
            OrtSessionOptions *options = nullptr;
            check(api->CreateSessionOptions(&options));
            try {
                check(api->SetIntraOpNumThreads(options, 2));
                check(api->SetInterOpNumThreads(options, 1));
                check(api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL));
                check(api->CreateSession(env, model, options, &session));
            } catch (...) { api->ReleaseSessionOptions(options); throw; }
            api->ReleaseSessionOptions(options);
        } catch (...) {
            if (env) api->ReleaseEnv(env);
            env = nullptr;
            throw;
        }
    }
    std::vector<uint8_t> run(std::vector<uint8_t> &image, std::vector<uint8_t> &mask, int w, int h) {
        OrtMemoryInfo *memory = nullptr;
        OrtValue *inputImage = nullptr, *inputMask = nullptr, *output = nullptr;
        OrtTensorTypeAndShapeInfo *shape = nullptr;
        auto cleanup = [&] {
            if (shape) api->ReleaseTensorTypeAndShapeInfo(shape);
            if (output) api->ReleaseValue(output);
            if (inputMask) api->ReleaseValue(inputMask);
            if (inputImage) api->ReleaseValue(inputImage);
            if (memory) api->ReleaseMemoryInfo(memory);
        };
        try {
            check(api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory));
            const int64_t imageShape[] = {1, 3, h, w}, maskShape[] = {1, 1, h, w};
            check(api->CreateTensorWithDataAsOrtValue(memory, image.data(), image.size(), imageShape, 4,
                                                     ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8, &inputImage));
            check(api->CreateTensorWithDataAsOrtValue(memory, mask.data(), mask.size(), maskShape, 4,
                                                     ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8, &inputMask));
            const char *names[] = {"image", "mask"}, *outputNames[] = {"result"};
            const OrtValue *inputs[] = {inputImage, inputMask};
            check(api->Run(session, nullptr, names, inputs, 2, outputNames, 1, &output));
            check(api->GetTensorTypeAndShape(output, &shape));
            ONNXTensorElementDataType type;
            size_t count = 0, dimensions = 0;
            check(api->GetTensorElementType(shape, &type));
            check(api->GetTensorShapeElementCount(shape, &count));
            check(api->GetDimensionsCount(shape, &dimensions));
            int64_t dims[4] = {};
            if (dimensions != 4) throw std::runtime_error("Unexpected model output rank");
            check(api->GetDimensions(shape, dims, 4));
            if (type != ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8 || count != image.size() ||
                dims[0] != 1 || dims[1] != 3 || dims[2] != h || dims[3] != w)
                throw std::runtime_error("Unexpected model output dimensions");
            void *data = nullptr;
            check(api->GetTensorMutableData(output, &data));
            auto begin = static_cast<uint8_t *>(data);
            std::vector<uint8_t> result(begin, begin + count);
            cleanup();
            return result;
        } catch (...) { cleanup(); throw; }
    }
};
// Keep the runtime session alive until process teardown.  ONNX Runtime owns
// worker state that can outlive the Swift UI; destroying it during C++ static
// teardown races libc++'s synchronization objects on macOS.  The process is
// exiting at that point, so an intentional small leak is safer than a crash.
std::mutex *inferenceMutex = new std::mutex();
ModelSession *modelSession = nullptr;
}

int imagepro_inpaint(uint8_t *rgba, const uint8_t *coverage, size_t width, size_t height,
                     float opacity, const char *model_path,
                     const char *runtime_path, char *error, size_t error_capacity) {
    if (error && error_capacity) error[0] = 0;
    try {
        if (!rgba || !coverage || !width || !height || width > 8192 || height > 8192 ||
            width * height > 40000000 || !std::isfinite(opacity))
            throw std::runtime_error("Invalid image or repair parameters");
        opacity = std::clamp(opacity, 0.0f, 1.0f);
        if (opacity == 0) return 0;
        int minX = (int)width, minY = (int)height, maxX = -1, maxY = -1;
        for (int y = 0; y < (int)height; ++y) for (int x = 0; x < (int)width; ++x)
            if (coverage[y * width + x]) {
                minX = std::min(minX, x); minY = std::min(minY, y);
                maxX = std::max(maxX, x); maxY = std::max(maxY, y);
            }
        if (maxX < minX) return 0;
        // Keep context while bounding model preprocessing to the affected neighborhood.
        int padding = std::max(64, std::max(maxX - minX, maxY - minY) / 2);
        int x0 = std::max(0, minX - padding), y0 = std::max(0, minY - padding);
        int w = std::min((int)width, maxX + padding + 1) - x0;
        int h = std::min((int)height, maxY + padding + 1) - y0;
        std::vector<uint8_t> rgb((size_t)w * h * 3), mask((size_t)w * h);
        size_t holes = 0;
        for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
            size_t source = (y + y0) * width + x + x0, p = y * w + x;
            uint8_t alpha = rgba[source * 4 + 3];
            for (int c = 0; c < 3; ++c)
                rgb[p * 3 + c] = alpha ? std::min(255, (rgba[source * 4 + c] * 255 + alpha / 2) / alpha) : 0;
            mask[p] = coverage[source] ? 255 : 0;
            holes += mask[p] != 0;
        }
        if (holes == mask.size()) throw std::runtime_error("The repair area needs surrounding image pixels");
        if (!model_path || !*model_path || !runtime_path || !*runtime_path)
            throw std::runtime_error("The bundled MI-GAN model or runtime is missing");
        const size_t plane = (size_t)w * h;
        std::vector<uint8_t> nchw(plane * 3), knownMask(plane);
        for (size_t p = 0; p < plane; ++p) {
            knownMask[p] = mask[p] ? 0 : 255;
            for (int c = 0; c < 3; ++c) nchw[c * plane + p] = rgb[p * 3 + c];
        }
        std::lock_guard<std::mutex> lock(*inferenceMutex);
        if (!modelSession || modelSession->path != model_path)
            modelSession = new ModelSession(model_path, runtime_path);
        auto result = modelSession->run(nchw, knownMask, w, h);
        std::vector<uint8_t> generated(plane * 3);
        for (size_t p = 0; p < plane; ++p) for (int c = 0; c < 3; ++c)
            generated[p * 3 + c] = result[c * plane + p];
        // Ordinary coverage compositing only; preserve original resolution and alpha.
        // No source-patch search or gradient-domain blend is performed here.
        for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
            size_t source = (y + y0) * width + x + x0, p = y * w + x;
            if (!coverage[source]) continue;
            const float amount = opacity * coverage[source] / 255.0f;
            const float alpha = rgba[source * 4 + 3] / 255.0f;
            for (int c = 0; c < 3; ++c) {
                float before = rgba[source * 4 + c], after = generated[p * 3 + c] * alpha;
                rgba[source * 4 + c] = (uint8_t)std::clamp(std::lround(before + (after - before) * amount), 0L, 255L);
            }
        }
        return 0;
    } catch (const std::exception &e) {
        if (error && error_capacity) std::snprintf(error, error_capacity, "%s", e.what());
        return -1;
    } catch (...) {
        if (error && error_capacity) std::snprintf(error, error_capacity, "Image repair failed");
        return -1;
    }
}
