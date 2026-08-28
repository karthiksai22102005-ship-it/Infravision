// Define Windows 8 target for MFSTARTUP_NOSOCK and Media Foundation APIs.
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0602
#endif

#include "infravision_camera_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <windows.h>
#include <wincodec.h>/*  */
#include <wrl/client.h>

#include <atomic>
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdarg>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "windowscodecs.lib")

using Microsoft::WRL::ComPtr;
using namespace flutter;

namespace infravision_camera {

namespace {

// Helper to convert a wide string to UTF-8.
std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  int size_needed = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.length()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.length()), result.data(), size_needed,
                      nullptr, nullptr);
  return result;
}

// Helper to convert UTF-8 to wide string.
std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size_needed = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.length()), nullptr, 0);
  std::wstring result(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.length()), result.data(), size_needed);
  return result;
}

// Get a device friendly name from an attribute store.
std::wstring GetDeviceName(IMFActivate* activate) {
  wchar_t* name = nullptr;
  UINT32 length = 0;
  if (SUCCEEDED(activate->GetAllocatedString(
          MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &name, &length))) {
    std::wstring result(name);
    CoTaskMemFree(name);
    return result;
  }
  return L"Unknown Camera";
}

// Get a device symbolic link (unique id) from an attribute store.
std::wstring GetDeviceId(IMFActivate* activate) {
  wchar_t* id = nullptr;
  UINT32 length = 0;
  if (SUCCEEDED(activate->GetAllocatedString(
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, &id,
          &length))) {
    std::wstring result(id);
    CoTaskMemFree(id);
    return result;
  }
  return L"";
}

std::string ToHex(HRESULT hr) {
  char buf[16];
  snprintf(buf, sizeof(buf), "%08X", static_cast<unsigned int>(hr));
  return std::string(buf);
}

// Convert a GUID subtype to a human-readable string.
std::string SubtypeToString(const GUID& subtype) {
  if (subtype == MFVideoFormat_RGB32) return "BGRA32";
  if (subtype == MFVideoFormat_RGB24) return "RGB24";
  if (subtype == MFVideoFormat_NV12) return "NV12";
  if (subtype == MFVideoFormat_YUY2) return "YUY2";
  if (subtype == MFVideoFormat_MJPG) return "MJPEG";
  if (subtype == MFVideoFormat_I420) return "I420";
  char buf[64];
  snprintf(buf, sizeof(buf), "Unknown(%.8X)", static_cast<unsigned int>(subtype.Data1));
  return std::string(buf);
}

// Convert NV12 to RGBA32.
// NV12: Y plane (width*height), then interleaved UV plane (width*height/2).
void NV12ToBGRA(const uint8_t* nv12, uint8_t* rgba, int width, int height) {
  int y_size = width * height;
  const uint8_t* y_plane = nv12;
  const uint8_t* uv_plane = nv12 + y_size;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      int idx = y * width + x;
      int uv_idx = ((y / 2) * (width / 2) + (x / 2)) * 2;
      int yv = y_plane[idx];
      int uv = uv_plane[uv_idx];
      int vv = uv_plane[uv_idx + 1];
      // Standard BT.601 YUV -> RGB conversion
      int c = yv - 16;
      int d = uv - 128;
      int e = vv - 128;
      int r = (298 * c + 409 * e + 128) >> 8;
      int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
      int b = (298 * c + 516 * d + 128) >> 8;
      r = r < 0 ? 0 : (r > 255 ? 255 : r);
      g = g < 0 ? 0 : (g > 255 ? 255 : g);
      b = b < 0 ? 0 : (b > 255 ? 255 : b);
      int out_idx = (y * width + x) * 4;
      rgba[out_idx + 0] = static_cast<uint8_t>(r);
      rgba[out_idx + 1] = static_cast<uint8_t>(g);
      rgba[out_idx + 2] = static_cast<uint8_t>(b);
      rgba[out_idx + 3] = 255;
    }
  }
}

// Convert YUY2 to RGBA32.
// YUY2: each macropixel is 4 bytes: Y0 U0 Y1 V0
void YUY2ToBGRA(const uint8_t* yuy2, uint8_t* rgba, int width, int height) {
  for (int y = 0; y < height; y++) {
    const uint8_t* row = yuy2 + y * width * 2;
    for (int x = 0; x < width; x += 2) {
      int y0 = row[x * 2 + 0];
      int u0 = row[x * 2 + 1];
      int y1 = row[x * 2 + 2];
      int v0 = row[x * 2 + 3];

      int c0 = y0 - 16;
      int c1 = y1 - 16;
      int d = u0 - 128;
      int e = v0 - 128;

      int r0 = (298 * c0 + 409 * e + 128) >> 8;
      int g0 = (298 * c0 - 100 * d - 208 * e + 128) >> 8;
      int b0 = (298 * c0 + 516 * d + 128) >> 8;
      r0 = r0 < 0 ? 0 : (r0 > 255 ? 255 : r0);
      g0 = g0 < 0 ? 0 : (g0 > 255 ? 255 : g0);
      b0 = b0 < 0 ? 0 : (b0 > 255 ? 255 : b0);

      int r1 = (298 * c1 + 409 * e + 128) >> 8;
      int g1 = (298 * c1 - 100 * d - 208 * e + 128) >> 8;
      int b1 = (298 * c1 + 516 * d + 128) >> 8;
      r1 = r1 < 0 ? 0 : (r1 > 255 ? 255 : r1);
      g1 = g1 < 0 ? 0 : (g1 > 255 ? 255 : g1);
      b1 = b1 < 0 ? 0 : (b1 > 255 ? 255 : b1);

      int out_idx = (y * width + x) * 4;
      rgba[out_idx + 0] = static_cast<uint8_t>(r0);
      rgba[out_idx + 1] = static_cast<uint8_t>(g0);
      rgba[out_idx + 2] = static_cast<uint8_t>(b0);
      rgba[out_idx + 3] = 255;
      rgba[out_idx + 4] = static_cast<uint8_t>(r1);
      rgba[out_idx + 5] = static_cast<uint8_t>(g1);
      rgba[out_idx + 6] = static_cast<uint8_t>(b1);
      rgba[out_idx + 7] = 255;
    }
  }
}

// Convert I420 to RGBA32.
void I420ToBGRA(const uint8_t* i420, uint8_t* rgba, int width, int height) {
  int y_size = width * height;
  int uv_size = (width / 2) * (height / 2);
  const uint8_t* y_plane = i420;
  const uint8_t* u_plane = i420 + y_size;
  const uint8_t* v_plane = i420 + y_size + uv_size;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      int yv = y_plane[y * width + x];
      int uv_idx = (y / 2) * (width / 2) + (x / 2);
      int u = u_plane[uv_idx];
      int v = v_plane[uv_idx];

      int c = yv - 16;
      int d = u - 128;
      int e = v - 128;
      int r = (298 * c + 409 * e + 128) >> 8;
      int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
      int b = (298 * c + 516 * d + 128) >> 8;
      r = r < 0 ? 0 : (r > 255 ? 255 : r);
      g = g < 0 ? 0 : (g > 255 ? 255 : g);
      b = b < 0 ? 0 : (b > 255 ? 255 : b);

      int out_idx = (y * width + x) * 4;
      rgba[out_idx + 0] = static_cast<uint8_t>(r);
      rgba[out_idx + 1] = static_cast<uint8_t>(g);
      rgba[out_idx + 2] = static_cast<uint8_t>(b);
      rgba[out_idx + 3] = 255;
    }
  }
}

int64_t MonotonicMicros() {
  using clock = std::chrono::steady_clock;
  return std::chrono::duration_cast<std::chrono::microseconds>(
             clock::now().time_since_epoch())
      .count();
}

void FillOpaqueBlack(std::vector<uint8_t>* rgba) {
  std::fill(rgba->begin(), rgba->end(), static_cast<uint8_t>(0));
  for (size_t i = 3; i < rgba->size(); i += 4) {
    (*rgba)[i] = 255;
  }
}

// Media Foundation RGB24 uses Windows DIB byte order: B, G, R. Convert to RGBA.
void RGB24ToBGRA(const uint8_t* rgb24, size_t length, uint8_t* rgba,
                 int width, int height, int stride) {
  const size_t row_bytes = static_cast<size_t>(width) * 3;
  int source_stride = stride == 0 ? static_cast<int>(row_bytes) : stride;
  int absolute_stride = source_stride < 0 ? -source_stride : source_stride;
  if (absolute_stride <= 0) {
    absolute_stride = static_cast<int>(row_bytes);
    source_stride = absolute_stride;
  }

  for (int y = 0; y < height; y++) {
    const int source_row = source_stride < 0 ? (height - 1 - y) : y;
    const size_t source_offset =
        static_cast<size_t>(source_row) * absolute_stride;
    if (source_offset >= length) break;
    const uint8_t* row = rgb24 + source_offset;
    for (int x = 0; x < width; x++) {
      const size_t pixel_offset = static_cast<size_t>(x) * 3;
      if (source_offset + pixel_offset + 2 >= length) break;
      const int out_idx = (y * width + x) * 4;
      rgba[out_idx + 0] = row[pixel_offset + 2]; // R
      rgba[out_idx + 1] = row[pixel_offset + 1]; // G
      rgba[out_idx + 2] = row[pixel_offset + 0]; // B
      rgba[out_idx + 3] = 255;
    }
  }
}

// Decode a JPEG/MJPEG frame to RGBA32 using Windows Imaging Component.
bool DecodeJpegToBGRA(const uint8_t* jpeg, size_t jpeg_length,
                      std::vector<uint8_t>* rgba, int* out_width,
                      int* out_height) {
  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory));
  if (FAILED(hr)) return false;

  ComPtr<IWICStream> stream;
  hr = factory->CreateStream(&stream);
  if (FAILED(hr)) return false;

  hr = stream->InitializeFromMemory(const_cast<BYTE*>(jpeg),
                                    static_cast<DWORD>(jpeg_length));
  if (FAILED(hr)) return false;

  ComPtr<IWICBitmapDecoder> decoder;
  hr = factory->CreateDecoderFromStream(stream.Get(), nullptr,
                                        WICDecodeMetadataCacheOnLoad,
                                        &decoder);
  if (FAILED(hr)) return false;

  ComPtr<IWICBitmapFrameDecode> frame;
  hr = decoder->GetFrame(0, &frame);
  if (FAILED(hr)) return false;

  UINT w = 0, h = 0;
  hr = frame->GetSize(&w, &h);
  if (FAILED(hr) || w == 0 || h == 0) return false;

  ComPtr<IWICFormatConverter> converter;
  hr = factory->CreateFormatConverter(&converter);
  if (FAILED(hr)) return false;

  hr = converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppRGBA,
                             WICBitmapDitherTypeNone, nullptr, 0.0,
                             WICBitmapPaletteTypeCustom);
  if (FAILED(hr)) return false;

  rgba->resize(static_cast<size_t>(w) * h * 4);
  hr = converter->CopyPixels(nullptr, w * 4,
                             static_cast<UINT>(rgba->size()),
                             rgba->data());
  if (FAILED(hr)) return false;

  *out_width = static_cast<int>(w);
  *out_height = static_cast<int>(h);
  return true;
}

// Copy Windows Media Foundation BGRA32 (B, G, R, A) into Flutter's RGBA32 buffer.
void CopyBgraWithStride(const uint8_t* src, size_t src_length,
                        std::vector<uint8_t>* dst, int width, int height,
                        int stride) {
  const size_t row_bytes = static_cast<size_t>(width) * 4;
  int source_stride = stride == 0 ? static_cast<int>(row_bytes) : stride;
  int absolute_stride = source_stride < 0 ? -source_stride : source_stride;

  if (absolute_stride <= 0) {
    absolute_stride = static_cast<int>(row_bytes);
    source_stride = absolute_stride;
  }

  if (src_length < static_cast<size_t>(absolute_stride) * height &&
      src_length >= row_bytes * height) {
    absolute_stride = static_cast<int>(row_bytes);
    source_stride = absolute_stride;
  }

  FillOpaqueBlack(dst);
  for (int y = 0; y < height; y++) {
    const int source_row =
        source_stride < 0 ? (height - 1 - y) : y;
    const size_t source_offset =
        static_cast<size_t>(source_row) * absolute_stride;
    if (source_offset >= src_length) break;

    const uint8_t* row = src + source_offset;
    for (int x = 0; x < width; x++) {
      const size_t px = static_cast<size_t>(x) * 4;
      if (source_offset + px + 3 >= src_length) break;
      const size_t out_idx = (static_cast<size_t>(y) * width + x) * 4;
      // Convert B, G, R, A -> R, G, B, A
      dst->data()[out_idx + 0] = row[px + 2]; // R
      dst->data()[out_idx + 1] = row[px + 1]; // G
      dst->data()[out_idx + 2] = row[px + 0]; // B
      dst->data()[out_idx + 3] = 255;
    }
  }
}

struct TextureFrameLease {
  std::shared_ptr<std::vector<uint8_t>> bytes;
  FlutterDesktopPixelBuffer pixel_buffer{};
};

void ReleaseTextureFrame(void* context) {
  delete static_cast<TextureFrameLease*>(context);
}

// Debug logging helper (free function in anonymous namespace to avoid
// being exported by WINDOWS_EXPORT_ALL_SYMBOLS).
void LogDebug(const char* fmt, ...) {
  char buf[1024];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  OutputDebugStringA(buf);
  OutputDebugStringA("\n");
}

int CaptureSubtypeRank(const GUID& subtype) {
  // Lower rank = better. RGB24/RGB32 carry full color (no chroma
  // subsampling), so they are ranked first for full-color fidelity. YUY2
  // has 4:2:2 subsampling (better) and NV12/I420 have 4:2:0.
  if (subtype == MFVideoFormat_RGB32) return 0;
  if (subtype == MFVideoFormat_RGB24) return 1;
  if (subtype == MFVideoFormat_YUY2) return 2;
  if (subtype == MFVideoFormat_NV12) return 3;
  if (subtype == MFVideoFormat_I420) return 4;
  if (subtype == MFVideoFormat_MJPG) return 5;
  return -1;
}

int AbsInt(int value) {
  return value < 0 ? -value : value;
}

// Find the highest native resolution the camera supports. This is used to
// request full-resolution output rather than a fixed 720p preview.
bool FindBestResolution(IMFSourceReader* reader, UINT32* width,
                        UINT32* height) {
  UINT32 best_width = 0;
  UINT32 best_height = 0;
  for (DWORD index = 0;; index++) {
    ComPtr<IMFMediaType> media_type;
    HRESULT hr = reader->GetNativeMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), index,
        &media_type);
    if (hr == MF_E_NO_MORE_TYPES) break;
    if (FAILED(hr)) continue;

    GUID major_type = {0};
    if (FAILED(media_type->GetGUID(MF_MT_MAJOR_TYPE, &major_type)) ||
        major_type != MFMediaType_Video) {
      continue;
    }
    UINT32 w = 0, h = 0;
    if (FAILED(MFGetAttributeSize(media_type.Get(), MF_MT_FRAME_SIZE, &w, &h)) ||
        w == 0 || h == 0) {
      continue;
    }
    uint64_t area = static_cast<uint64_t>(w) * h;
    uint64_t best_area = static_cast<uint64_t>(best_width) * best_height;
    if (area > best_area) {
      best_width = w;
      best_height = h;
    }
  }
  if (best_width == 0 || best_height == 0) return false;
  *width = best_width;
  *height = best_height;
  return true;
}

bool SelectNativeVideoType(IMFSourceReader* reader,
                           ComPtr<IMFMediaType>* selected_type) {
  // Score prefers the largest (highest) resolution for each color subtype so
  // we end up with full-resolution, best-color output.
  int best_score = 2147483647;
  ComPtr<IMFMediaType> best_type;
  GUID best_subtype = {0};
  UINT32 best_width = 0;
  UINT32 best_height = 0;
  UINT32 best_fps = 0;

  for (DWORD index = 0;; index++) {
    ComPtr<IMFMediaType> media_type;
    HRESULT hr = reader->GetNativeMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), index,
        &media_type);
    if (hr == MF_E_NO_MORE_TYPES) break;
    if (FAILED(hr)) continue;

    GUID major_type = {0};
    GUID subtype = {0};
    if (FAILED(media_type->GetGUID(MF_MT_MAJOR_TYPE, &major_type)) ||
        major_type != MFMediaType_Video ||
        FAILED(media_type->GetGUID(MF_MT_SUBTYPE, &subtype))) {
      continue;
    }

    const int subtype_rank = CaptureSubtypeRank(subtype);
    if (subtype_rank < 0) continue;

    UINT32 width = 0;
    UINT32 height = 0;
    if (FAILED(MFGetAttributeSize(media_type.Get(), MF_MT_FRAME_SIZE, &width,
                                  &height)) ||
        width == 0 || height == 0) {
      continue;
    }

    UINT32 fps_num = 0;
    UINT32 fps_den = 0;
    MFGetAttributeRatio(media_type.Get(), MF_MT_FRAME_RATE, &fps_num,
                        &fps_den);
    const int fps = fps_den > 0 ? static_cast<int>(fps_num / fps_den) : 30;

    // Larger resolution => lower (better) score within the same subtype.
    const uint64_t area = static_cast<uint64_t>(width) * height;
    const int64_t size_score =
        std::max<int64_t>(0, 100000000 - static_cast<int64_t>(area));
    // Mild preference for smooth 30 fps.
    const int fps_score = AbsInt((fps <= 0 ? 30 : fps) - 30) * 2500;
    const int64_t score =
        static_cast<int64_t>(subtype_rank) * 100000000 + size_score + fps_score;

    if (!best_type || score < best_score) {
      best_score = static_cast<int>(score);
      best_type = media_type;
      best_subtype = subtype;
      best_width = width;
      best_height = height;
      best_fps = static_cast<UINT32>(fps <= 0 ? 30 : fps);
    }
  }

  if (!best_type) return false;

  *selected_type = best_type;
  LogDebug("Selected native camera mode: %ux%u @ %u fps %s", best_width,
           best_height, best_fps, SubtypeToString(best_subtype).c_str());
  return true;
}

bool TrySetBgraOutputType(IMFSourceReader* reader, int width, int height,
                          int fps) {
  ComPtr<IMFMediaType> output_type;
  HRESULT hr = MFCreateMediaType(&output_type);
  if (FAILED(hr)) return false;

  output_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  output_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  MFSetAttributeSize(output_type.Get(), MF_MT_FRAME_SIZE, width, height);
  MFSetAttributeRatio(output_type.Get(), MF_MT_FRAME_RATE, fps, 1);

  hr = reader->SetCurrentMediaType(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
      output_type.Get());
  if (SUCCEEDED(hr)) {
    LogDebug("Selected converted camera mode: %dx%d @ %d fps BGRA32", width,
             height, fps);
    return true;
  }

  LogDebug("SetCurrentMediaType(BGRA32 %dx%d @ %d) failed: 0x%s", width,
           height, fps, ToHex(hr).c_str());
  return false;
}

}  // namespace

// ---------------------------------------------------------------------------
// CameraSession — owns the Media Foundation source reader and texture.
// ---------------------------------------------------------------------------
class InfravisionCameraPlugin::CameraSession {
 public:
  CameraSession(InfravisionCameraPlugin* plugin,
                flutter::TextureRegistrar* texture_registrar)
      : plugin_(plugin), texture_registrar_(texture_registrar) {}

  ~CameraSession() { Stop(); }

  bool Start(const std::wstring& device_id, int requested_width,
             int requested_height, std::string* error) {
    if (running_) {
      *error = "Camera already running";
      return false;
    }

    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (FAILED(hr)) {
      *error = "MFStartup failed: 0x" + ToHex(hr);
      return false;
    }
    mf_started_ = true;

    // Create the media source from the device symbolic link.
    ComPtr<IMFMediaSource> source;
    hr = CreateDeviceSource(device_id, &source);
    if (FAILED(hr)) {
      *error = "Failed to create media source: 0x" + ToHex(hr);
      Stop();
      return false;
    }

    // Configure the source reader.
    ComPtr<IMFAttributes> attributes;
    hr = MFCreateAttributes(&attributes, 3);
    if (FAILED(hr)) {
      *error = "MFCreateAttributes failed: 0x" + ToHex(hr);
      Stop();
      return false;
    }
    attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
    attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);

    hr = MFCreateSourceReaderFromMediaSource(source.Get(), attributes.Get(),
                                             &reader_);
    if (FAILED(hr)) {
      *error = "MFCreateSourceReaderFromMediaSource failed: 0x" + ToHex(hr);
      Stop();
      return false;
    }

    hr = reader_->SetStreamSelection(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), TRUE);
    if (FAILED(hr)) {
      *error = "SetStreamSelection(video) failed: 0x" + ToHex(hr);
      Stop();
      return false;
    }

    // Use the requested resolution or find the best native resolution.
    UINT32 full_width = 0, full_height = 0;
    if (requested_width > 0 && requested_height > 0) {
      full_width = static_cast<UINT32>(requested_width);
      full_height = static_cast<UINT32>(requested_height);
    } else if (!FindBestResolution(reader_.Get(), &full_width, &full_height)) {
      full_width = 1280;
      full_height = 720;
    }

    // Find a matching native frame rate for the target resolution.
    UINT32 target_fps = 30;
    for (DWORD index = 0;; index++) {
      ComPtr<IMFMediaType> mt;
      if (FAILED(reader_->GetNativeMediaType(0, index, &mt))) break;
      UINT32 w = 0, h = 0, num = 0, den = 0;
      if (SUCCEEDED(MFGetAttributeSize(mt.Get(), MF_MT_FRAME_SIZE, &w, &h)) &&
          w == full_width && h == full_height) {
        if (SUCCEEDED(MFGetAttributeRatio(mt.Get(), MF_MT_FRAME_RATE, &num,
                                          &den)) &&
            den > 0) {
          target_fps = num / den;
          break;
        }
      }
    }

    bool media_type_set = TrySetBgraOutputType(
        reader_.Get(), static_cast<int>(full_width),
        static_cast<int>(full_height), static_cast<int>(target_fps));

    if (!media_type_set) {
      // Fallback: try standard frame rates if the exact native FPS failed.
      for (int f : {30, 24, 15, 10}) {
        if (f == static_cast<int>(target_fps)) continue;
        if (TrySetBgraOutputType(reader_.Get(), static_cast<int>(full_width),
                                 static_cast<int>(full_height), f)) {
          media_type_set = true;
          break;
        }
      }
    }

    if (!media_type_set) {
      ComPtr<IMFMediaType> output_type;
      hr = MFCreateMediaType(&output_type);
      if (SUCCEEDED(hr)) {
        output_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        output_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
        hr = reader_->SetCurrentMediaType(
            static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
            output_type.Get());
        media_type_set = SUCCEEDED(hr);
      }
    }

    if (!media_type_set) {
      ComPtr<IMFMediaType> native_type;
      if (SelectNativeVideoType(reader_.Get(), &native_type)) {
        hr = reader_->SetCurrentMediaType(
            static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
            native_type.Get());
        if (SUCCEEDED(hr)) {
          media_type_set = true;
        } else {
          LogDebug("SetCurrentMediaType(native) failed: 0x%s",
                   ToHex(hr).c_str());
        }
      }
    }

    if (!media_type_set) {
      *error = "SetCurrentMediaType(video) failed";
      Stop();
      return false;
    }

    // Read the negotiated media type to get dimensions and actual format.
    ComPtr<IMFMediaType> negotiated_type;
    hr = reader_->GetCurrentMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM),
        &negotiated_type);
    if (FAILED(hr)) {
      *error = "GetCurrentMediaType failed: 0x" + ToHex(hr);
      Stop();
      return false;
    }

    // Get the actual subtype (may differ from what we requested if MF
    // couldn't convert).
    GUID subtype = {0};
    negotiated_type->GetGUID(MF_MT_SUBTYPE, &subtype);
    pixel_format_ = SubtypeToString(subtype);

    UINT32 width = 0, height = 0;
    MFGetAttributeSize(negotiated_type.Get(), MF_MT_FRAME_SIZE, &width,
                       &height);
    if (width == 0 || height == 0) {
      width = 640;
      height = 480;
    }
    width_ = static_cast<int>(width);
    height_ = static_cast<int>(height);

    // Get the frame rate.
    UINT32 fps_num = 0, fps_den = 0;
    MFGetAttributeRatio(negotiated_type.Get(), MF_MT_FRAME_RATE, &fps_num,
                        &fps_den);
    fps_ = (fps_den > 0) ? static_cast<int>(fps_num / fps_den) : 30;
    if (fps_ <= 0) fps_ = 30;

    // Get the stride (may be needed for some formats).
    UINT32 stride = 0;
    negotiated_type->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride);
    stride_ = static_cast<int>(static_cast<int32_t>(stride));
    if (stride_ == 0) {
      if (pixel_format_ == "BGRA32") {
        stride_ = width_ * 4;
      } else if (pixel_format_ == "RGB24") {
        stride_ = width_ * 3;
      } else if (pixel_format_ == "YUY2") {
        stride_ = width_ * 2;
      } else {
        stride_ = width_;
      }
    }

    has_frame_ = false;

    // Create the Flutter texture with immutable frame snapshots. The texture
    // callback returns a small lease object whose shared_ptr keeps the pixels
    // alive until Flutter calls the release callback.
    texture_ = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture(
            [this](size_t width, size_t height)
                -> const FlutterDesktopPixelBuffer* {
              std::shared_ptr<std::vector<uint8_t>> frame;
              int w = 0, h = 0;
              {
                std::lock_guard<std::mutex> lock(mutex_);
                frame = active_frame_;
                w = width_;
                h = height_;
              }

              if (!frame || frame->empty() || w <= 0 || h <= 0) {
                return nullptr;
              }

              auto lease = new TextureFrameLease();
              lease->bytes = std::move(frame);
              lease->pixel_buffer.buffer = lease->bytes->data();
              lease->pixel_buffer.width = static_cast<size_t>(w);
              lease->pixel_buffer.height = static_cast<size_t>(h);
              lease->pixel_buffer.release_callback = ReleaseTextureFrame;
              lease->pixel_buffer.release_context = lease;
              return &lease->pixel_buffer;
            }));
    texture_id_ = texture_registrar_->RegisterTexture(texture_.get());

    // Start the capture thread.
    running_ = true;
    capture_thread_ = std::thread([this]() { CaptureLoop(); });

    // Return immediately without blocking the platform UI thread.
    LogDebug("Camera session started successfully: %dx%d @ %d fps (format=%s, textureId=%lld)",
             width_, height_, fps_, pixel_format_.c_str(), static_cast<long long>(texture_id_));
    return true;
  }

  void Stop() {
    if (!running_ && !mf_started_) return;

    running_ = false;

    if (reader_) {
      reader_->Flush(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM));
    }

    if (capture_thread_.joinable()) {
      capture_thread_.join();
    }

    {
      std::lock_guard<std::mutex> lock(mutex_);
      has_frame_ = false;
      active_frame_.reset();
    }

    if (texture_id_ != -1 && texture_registrar_ != nullptr) {
      texture_registrar_->UnregisterTexture(texture_id_);
      texture_id_ = -1;
    }
    texture_.reset();

    if (reader_) {
      reader_.Reset();
    }

    if (mf_started_) {
      MFShutdown();
      mf_started_ = false;
    }
  }

  int64_t texture_id() const { return texture_id_; }
  int width() const { return width_; }
  int height() const { return height_; }
  int fps() const { return fps_; }
  const std::string& pixel_format() const { return pixel_format_; }
  int64_t frame_count() const { return frame_count_; }

 private:
  HRESULT CreateDeviceSource(const std::wstring& device_id,
                             IMFMediaSource** source) {
    HRESULT hr = E_FAIL;
    if (!device_id.empty()) {
      ComPtr<IMFAttributes> attributes;
      hr = MFCreateAttributes(&attributes, 2);
      if (SUCCEEDED(hr)) {
        attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                            MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
        attributes->SetString(
            MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
            device_id.c_str());
        hr = MFCreateDeviceSource(attributes.Get(), source);
      }
    }

    // If symbolic link creation failed or device_id was empty, fallback to activating via enum
    if (FAILED(hr) || *source == nullptr) {
      ComPtr<IMFAttributes> enum_attributes;
      if (SUCCEEDED(MFCreateAttributes(&enum_attributes, 1))) {
        enum_attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                                 MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
        IMFActivate** devices = nullptr;
        UINT32 count = 0;
        if (SUCCEEDED(MFEnumDeviceSources(enum_attributes.Get(), &devices, &count)) && count > 0) {
          UINT32 target_index = 0;
          if (!device_id.empty()) {
            for (UINT32 i = 0; i < count; i++) {
              std::wstring cur_id = GetDeviceId(devices[i]);
              if (cur_id == device_id) {
                target_index = i;
                break;
              }
            }
          }
          hr = devices[target_index]->ActivateObject(IID_PPV_ARGS(source));
          for (UINT32 i = 0; i < count; i++) {
            devices[i]->Release();
          }
          CoTaskMemFree(devices);
        }
      }
    }

    return hr;
  }

  void CaptureLoop() {
    const HRESULT com_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool did_initialize_com = SUCCEEDED(com_hr);
    if (FAILED(com_hr) && com_hr != RPC_E_CHANGED_MODE) {
      LogDebug("Capture thread CoInitializeEx failed: 0x%s",
               ToHex(com_hr).c_str());
      return;
    }

    bool read_error_logged = false;
    bool buffer_error_logged = false;
    while (running_) {
      ComPtr<IMFSample> sample;
      DWORD flags = 0;
      LONGLONG timestamp = 0;

      HRESULT hr = reader_->ReadSample(
          static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 0, nullptr,
          &flags, &timestamp, &sample);

      if (FAILED(hr)) {
        if (!read_error_logged) {
          read_error_logged = true;
          LogDebug("ReadSample failed: 0x%s", ToHex(hr).c_str());
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        continue;
      }
      read_error_logged = false;

      if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
        break;
      }

      if (sample == nullptr) {
        continue;
      }

      ComPtr<IMFMediaBuffer> buffer;
      hr = sample->ConvertToContiguousBuffer(&buffer);
      if (FAILED(hr)) {
        if (!buffer_error_logged) {
          buffer_error_logged = true;
          LogDebug("ConvertToContiguousBuffer failed: 0x%s",
                   ToHex(hr).c_str());
        }
        continue;
      }
      buffer_error_logged = false;

      BYTE* data = nullptr;
      DWORD max_length = 0;
      DWORD current_length = 0;
      hr = buffer->Lock(&data, &max_length, &current_length);
      if (FAILED(hr)) continue;

      if (data != nullptr && current_length > 0) {
        // The texture callback is asynchronous. Each produced frame gets its
        // own reference-counted storage so Flutter never reads memory while
        // the capture thread overwrites it.
        auto frame = std::make_shared<std::vector<uint8_t>>(
            static_cast<size_t>(width_) * height_ * 4);
        FillOpaqueBlack(frame.get());

        if (pixel_format_ == "BGRA32") {
          CopyBgraWithStride(data, static_cast<size_t>(current_length),
                             frame.get(), width_, height_, stride_);
        } else if (pixel_format_ == "RGB24") {
          RGB24ToBGRA(data, static_cast<size_t>(current_length), frame->data(),
                      width_, height_, stride_);
        } else if (pixel_format_ == "NV12") {
          NV12ToBGRA(data, frame->data(), width_, height_);
        } else if (pixel_format_ == "YUY2") {
          YUY2ToBGRA(data, frame->data(), width_, height_);
        } else if (pixel_format_ == "I420") {
          I420ToBGRA(data, frame->data(), width_, height_);
        } else if (pixel_format_ == "MJPEG") {
          // Decode the JPEG frame to full-color BGRA32.
          int decoded_w = 0, decoded_h = 0;
          if (DecodeJpegToBGRA(data, static_cast<size_t>(current_length),
                               frame.get(), &decoded_w, &decoded_h)) {
            if (decoded_w != width_ || decoded_h != height_) {
              // The decoded dimensions may differ from the negotiated ones;
              // update the frame size for this frame.
              width_ = decoded_w;
              height_ = decoded_h;
              stride_ = width_ * 4;
            }
          } else {
            LogDebug("MJPEG decode failed for %u bytes", current_length);
          }
        } else {
          // RGB32 is requested from Media Foundation, so this is diagnostic
          // fallback only for a device which negotiates an unexpected format.
          CopyBgraWithStride(data, static_cast<size_t>(current_length),
                             frame.get(), width_, height_, width_ * 4);
        }

        const int64_t timestamp_us = MonotonicMicros();
        bool is_first_frame = false;
        {
          std::lock_guard<std::mutex> lock(mutex_);
          active_frame_ = frame;
          frame_count_++;
          if (!has_frame_) {
            has_frame_ = true;
            is_first_frame = true;
            first_frame_cv_.notify_all();
          }
        }

        if (is_first_frame) {
          LogDebug("First frame: %dx%d source_format=%s "
                   "delivered_format=BGRA32 stride=%d mf_timestamp=%lld "
                   "monotonic_us=%lld buffer_size=%u",
                   width_, height_, pixel_format_.c_str(), stride_,
                   static_cast<long long>(timestamp),
                   static_cast<long long>(timestamp_us), current_length);
        }

        if (texture_registrar_ != nullptr && texture_id_ != -1) {
          texture_registrar_->MarkTextureFrameAvailable(texture_id_);
        }
        if (plugin_ != nullptr) {
          plugin_->QueueFrame(frame->data(), frame->size(), width_, height_,
                              timestamp_us, "BGRA32");
        }

#if 0  // Retained temporarily for converter comparison; not compiled.
        // Determine which buffer to write to (double-buffering).
        int write_buffer = 1 - current_buffer_;
        std::vector<uint8_t>* target =
            (write_buffer == 0) ? &buffer_a_ : &buffer_b_;

        // Convert to BGRA32 if needed.
        // The negotiated type should be RGB32 (BGRA), but if the camera
        // produced a different format, we need to convert.
        // Since we requested MFVideoFormat_RGB32 and enabled video processing,
        // MF should have inserted a converter. But let's handle the case
        // where it didn't.
        if (pixel_format_ == "BGRA32") {
          // Already BGRA32 — just copy.
          size_t copy_size =
              std::min(static_cast<size_t>(current_length),
                       static_cast<size_t>(width_) * height_ * 4);
          {
            std::lock_guard<std::mutex> lock(mutex_);
            std::copy(data, data + copy_size, target->begin());
            active_buffer_ = target;
            current_buffer_ = write_buffer;
            frame_count_++;
            if (!has_frame_) {
              has_frame_ = true;
              first_frame_cv_.notify_all();
              // Log the first successful frame.
              LogDebug("First frame: %dx%d format=%s timestamp=%lld "
                         "buffer_size=%u",
                         width_, height_, pixel_format_.c_str(),
                         static_cast<long long>(timestamp), current_length);
            }
          }
        } else if (pixel_format_ == "NV12") {
          {
            std::lock_guard<std::mutex> lock(mutex_);
            NV12ToBGRA(data, target->data(), width_, height_);
            active_buffer_ = target;
            current_buffer_ = write_buffer;
            frame_count_++;
            if (!has_frame_) {
              has_frame_ = true;
              first_frame_cv_.notify_all();
              LogDebug("First frame: %dx%d format=%s timestamp=%lld "
                         "buffer_size=%u",
                         width_, height_, pixel_format_.c_str(),
                         static_cast<long long>(timestamp), current_length);
            }
          }
        } else if (pixel_format_ == "YUY2") {
          {
            std::lock_guard<std::mutex> lock(mutex_);
            YUY2ToBGRA(data, target->data(), width_, height_);
            active_buffer_ = target;
            current_buffer_ = write_buffer;
            frame_count_++;
            if (!has_frame_) {
              has_frame_ = true;
              first_frame_cv_.notify_all();
              LogDebug("First frame: %dx%d format=%s timestamp=%lld "
                         "buffer_size=%u",
                         width_, height_, pixel_format_.c_str(),
                         static_cast<long long>(timestamp), current_length);
            }
          }
        } else if (pixel_format_ == "I420") {
          {
            std::lock_guard<std::mutex> lock(mutex_);
            I420ToBGRA(data, target->data(), width_, height_);
            active_buffer_ = target;
            current_buffer_ = write_buffer;
            frame_count_++;
            if (!has_frame_) {
              has_frame_ = true;
              first_frame_cv_.notify_all();
              LogDebug("First frame: %dx%d format=%s timestamp=%lld "
                         "buffer_size=%u",
                         width_, height_, pixel_format_.c_str(),
                         static_cast<long long>(timestamp), current_length);
            }
          }
        } else if (pixel_format_ == "MJPEG") {
          // MJPEG — we need to decode it. For now, try to use the raw
          // buffer (MF may have already decoded it if video processing
          // is enabled). If not, we'll need a JPEG decoder.
          // Since we requested RGB32 output, MF should have decoded it.
          // If we're here, it means the format wasn't converted.
          // Fall through to raw copy as a best effort.
          size_t copy_size =
              std::min(static_cast<size_t>(current_length),
                       static_cast<size_t>(width_) * height_ * 4);
          {
            std::lock_guard<std::mutex> lock(mutex_);
            std::copy(data, data + copy_size, target->begin());
            active_buffer_ = target;
            current_buffer_ = write_buffer;
            frame_count_++;
            if (!has_frame_) {
              has_frame_ = true;
              first_frame_cv_.notify_all();
              LogDebug("First frame: %dx%d format=%s timestamp=%lld "
                         "buffer_size=%u",
                         width_, height_, pixel_format_.c_str(),
                         static_cast<long long>(timestamp), current_length);
            }
          }
        } else {
          // Unknown format — try raw copy as best effort.
          size_t copy_size =
              std::min(static_cast<size_t>(current_length),
                       static_cast<size_t>(width_) * height_ * 4);
          {
            std::lock_guard<std::mutex> lock(mutex_);
            std::copy(data, data + copy_size, target->begin());
            active_buffer_ = target;
            current_buffer_ = write_buffer;
            frame_count_++;
            if (!has_frame_) {
              has_frame_ = true;
              first_frame_cv_.notify_all();
              LogDebug("First frame: %dx%d format=%s timestamp=%lld "
                         "buffer_size=%u",
                         width_, height_, pixel_format_.c_str(),
                         static_cast<long long>(timestamp), current_length);
            }
          }
        }

        // Queue the frame for delivery on the platform thread.
        if (plugin_ != nullptr) {
          plugin_->QueueFrame(data, current_length, width_, height_,
                              static_cast<int64_t>(timestamp));
        }
#endif
      }

      buffer->Unlock();
    }

    if (did_initialize_com) {
      CoUninitialize();
    }
  }

  InfravisionCameraPlugin* plugin_;
  flutter::TextureRegistrar* texture_registrar_;

  ComPtr<IMFSourceReader> reader_;
  std::unique_ptr<flutter::TextureVariant> texture_;
  int64_t texture_id_ = -1;
  int width_ = 0;
  int height_ = 0;
  int fps_ = 30;
  int stride_ = 0;
  std::string pixel_format_ = "Unknown";
  int64_t frame_count_ = 0;

  std::shared_ptr<std::vector<uint8_t>> active_frame_;

  std::thread capture_thread_;
  std::atomic<bool> running_{false};
  bool mf_started_ = false;
  bool has_frame_ = false;

  std::mutex mutex_;
  std::condition_variable first_frame_cv_;
};

// ---------------------------------------------------------------------------
// Plugin implementation
// ---------------------------------------------------------------------------

void InfravisionCameraPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<
      flutter::EncodableValue>>(
      registrar->messenger(), "infravision_camera",
      &flutter::StandardMethodCodec::GetInstance());

  auto frame_channel = std::make_unique<flutter::MethodChannel<
      flutter::EncodableValue>>(
      registrar->messenger(), "infravision_camera/frames",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<InfravisionCameraPlugin>(
      registrar, std::move(channel), std::move(frame_channel));

  registrar->AddPlugin(std::move(plugin));
}

void InfravisionCameraPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  InfravisionCameraPlugin::RegisterWithRegistrar(registrar);
}

extern "C" FLUTTER_PLUGIN_EXPORT void InfravisionCameraPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  InfravisionCameraPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()->
          GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

InfravisionCameraPlugin::InfravisionCameraPlugin(
    flutter::PluginRegistrarWindows* registrar,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
        frame_channel)
    : registrar_(registrar),
      channel_(std::move(channel)),
      frame_channel_(std::move(frame_channel)) {
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  // Register a WindowProc delegate to receive our custom frame-ready
  // message on the platform thread.
  window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowMessage(hwnd, message, wparam, lparam);
      });
}

InfravisionCameraPlugin::~InfravisionCameraPlugin() {
  if (session_) {
    session_->Stop();
    session_.reset();
  }
  if (window_proc_delegate_id_ != -1) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
  }
}

void InfravisionCameraPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "availableCameras") {
    HandleAvailableCameras(std::move(result));
  } else if (method == "startCamera") {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments == nullptr) {
      result->Error("bad_args", "Expected a map of arguments");
      return;
    }

    auto it = arguments->find(flutter::EncodableValue("deviceId"));
    if (it == arguments->end()) {
      result->Error("bad_args", "Missing deviceId");
      return;
    }
    const auto* device_id = std::get_if<std::string>(&it->second);
    if (device_id == nullptr) {
      result->Error("bad_args", "deviceId must be a string");
      return;
    }

    int requested_width = 0;
    int requested_height = 0;
    auto w_it = arguments->find(flutter::EncodableValue("width"));
    if (w_it != arguments->end()) {
      if (auto width_value32 = std::get_if<int32_t>(&w_it->second))
        requested_width = *width_value32;
      else if (auto width_value64 = std::get_if<int64_t>(&w_it->second))
        requested_width = static_cast<int>(*width_value64);
    }
    auto h_it = arguments->find(flutter::EncodableValue("height"));
    if (h_it != arguments->end()) {
      if (auto height_value32 = std::get_if<int32_t>(&h_it->second))
        requested_height = *height_value32;
      else if (auto height_value64 = std::get_if<int64_t>(&h_it->second))
        requested_height = static_cast<int>(*height_value64);
    }

    HandleStartCamera(*device_id, requested_width, requested_height,
                      std::move(result));
  } else if (method == "stopCamera") {
    HandleStopCamera(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void InfravisionCameraPlugin::HandleAvailableCameras(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
  if (FAILED(hr)) {
    result->Error("mf_startup_failed", "MFStartup failed");
    return;
  }

  ComPtr<IMFAttributes> attributes;
  hr = MFCreateAttributes(&attributes, 1);
  if (FAILED(hr)) {
    MFShutdown();
    result->Error("mf_attributes_failed", "MFCreateAttributes failed");
    return;
  }

  hr = attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                           MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  if (FAILED(hr)) {
    MFShutdown();
    result->Error("mf_attributes_failed", "Failed to set source type");
    return;
  }

  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  hr = MFEnumDeviceSources(attributes.Get(), &devices, &count);
  if (FAILED(hr)) {
    MFShutdown();
    result->Error("mf_enum_failed", "MFEnumDeviceSources failed");
    return;
  }

  flutter::EncodableList device_list;
  for (UINT32 i = 0; i < count; i++) {
    std::wstring name = GetDeviceName(devices[i]);
    std::wstring id = GetDeviceId(devices[i]);

    // Enumerate supported resolutions for this device.
    std::vector<std::string> resolutions;
    ComPtr<IMFMediaSource> source;
    ComPtr<IMFAttributes> source_attr;
    if (SUCCEEDED(MFCreateAttributes(&source_attr, 2))) {
      source_attr->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                           MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
      source_attr->SetString(
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, id.c_str());
      if (SUCCEEDED(MFCreateDeviceSource(source_attr.Get(), &source))) {
        ComPtr<IMFSourceReader> temp_reader;
        ComPtr<IMFAttributes> reader_attr;
        MFCreateAttributes(&reader_attr, 1);
        reader_attr->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
        if (SUCCEEDED(MFCreateSourceReaderFromMediaSource(
                source.Get(), reader_attr.Get(), &temp_reader))) {
          for (DWORD mt_idx = 0;; mt_idx++) {
            ComPtr<IMFMediaType> mt;
            if (FAILED(temp_reader->GetNativeMediaType(0, mt_idx, &mt))) break;
            UINT32 w = 0, h = 0;
            if (SUCCEEDED(MFGetAttributeSize(mt.Get(), MF_MT_FRAME_SIZE, &w,
                                             &h)) &&
                w > 0 && h > 0) {
              char buf[32];
              snprintf(buf, sizeof(buf), "%ux%u", w, h);
              std::string res_str(buf);
              if (std::find(resolutions.begin(), resolutions.end(), res_str) ==
                  resolutions.end()) {
                resolutions.push_back(res_str);
              }
            }
          }
        }
      }
    }
    std::sort(resolutions.begin(), resolutions.end(),
              [](const std::string& a, const std::string& b) {
                int w1 = 0, h1 = 0, w2 = 0, h2 = 0;
                sscanf_s(a.c_str(), "%dx%d", &w1, &h1);
                sscanf_s(b.c_str(), "%dx%d", &w2, &h2);
                return (w1 * h1) > (w2 * h2);
              });

    flutter::EncodableMap device_map;
    device_map[flutter::EncodableValue("id")] =
        flutter::EncodableValue(WideToUtf8(id));
    device_map[flutter::EncodableValue("name")] =
        flutter::EncodableValue(WideToUtf8(name));

    flutter::EncodableList res_list;
    for (const auto& r : resolutions) {
      res_list.push_back(flutter::EncodableValue(r));
    }
    device_map[flutter::EncodableValue("resolutions")] =
        flutter::EncodableValue(res_list);

    device_list.push_back(flutter::EncodableValue(device_map));
    devices[i]->Release();
  }
  CoTaskMemFree(devices);

  MFShutdown();

  result->Success(flutter::EncodableValue(device_list));
}

void InfravisionCameraPlugin::HandleStartCamera(
    const std::string& device_id, int requested_width, int requested_height,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (session_) {
    result->Error("already_running", "Camera is already running");
    return;
  }

  auto texture_registrar = registrar_->texture_registrar();
  if (texture_registrar == nullptr) {
    result->Error("no_texture_registrar", "Texture registrar unavailable");
    return;
  }

  session_ = std::make_unique<CameraSession>(this, texture_registrar);

  std::string error;
  if (!session_->Start(Utf8ToWide(device_id), requested_width, requested_height,
                       &error)) {
    session_.reset();
    result->Error("camera_start_failed", error);
    return;
  }

  flutter::EncodableMap response;
  response[flutter::EncodableValue("textureId")] =
      flutter::EncodableValue(static_cast<int64_t>(session_->texture_id()));
  response[flutter::EncodableValue("width")] =
      flutter::EncodableValue(session_->width());
  response[flutter::EncodableValue("height")] =
      flutter::EncodableValue(session_->height());
  response[flutter::EncodableValue("fps")] =
      flutter::EncodableValue(session_->fps());
  response[flutter::EncodableValue("pixelFormat")] =
      flutter::EncodableValue(session_->pixel_format());

  result->Success(flutter::EncodableValue(response));
}

void InfravisionCameraPlugin::HandleStopCamera(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (session_) {
    session_->Stop();
    session_.reset();
  }
  result->Success();
}

void InfravisionCameraPlugin::QueueFrame(const uint8_t* data, size_t length,
                                         int width, int height,
                                         int64_t timestamp,
                                         const std::string& pixel_format) {
  {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    pending_frame_.assign(data, data + length);
    pending_width_ = width;
    pending_height_ = height;
    pending_timestamp_ = timestamp;
    pending_pixel_format_ = pixel_format;
    frame_pending_ = true;
  }

  // Post a message to the platform thread to deliver the frame.
  auto view = registrar_->GetView();
  if (view != nullptr) {
    HWND hwnd = view->GetNativeWindow();
    if (hwnd != nullptr) {
      HWND top_hwnd = GetAncestor(hwnd, GA_ROOT);
      if (top_hwnd != nullptr) {
        PostMessage(top_hwnd, kFrameReadyMessage, 0, 0);
      }
      PostMessage(hwnd, kFrameReadyMessage, 0, 0);
    }
  }
}

void InfravisionCameraPlugin::SendPendingFrame() {
  std::vector<uint8_t> bytes;
  int width = 0;
  int height = 0;
  int64_t timestamp = 0;
  std::string pixel_format;

  {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    if (!frame_pending_) return;
    bytes = std::move(pending_frame_);
    width = pending_width_;
    height = pending_height_;
    timestamp = pending_timestamp_;
    pixel_format = pending_pixel_format_;
    frame_pending_ = false;
  }

  flutter::EncodableMap frame_map;
  frame_map[flutter::EncodableValue("bytes")] =
      flutter::EncodableValue(bytes);
  frame_map[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
  frame_map[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
  frame_map[flutter::EncodableValue("timestamp")] =
      flutter::EncodableValue(timestamp);
  frame_map[flutter::EncodableValue("pixelFormat")] =
      flutter::EncodableValue(pixel_format);

  frame_channel_->InvokeMethod(
      "onFrame", std::make_unique<flutter::EncodableValue>(frame_map));

  // The texture is marked available in the capture loop, no need to do it here.
}

std::optional<LRESULT> InfravisionCameraPlugin::HandleWindowMessage(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kFrameReadyMessage) {
    SendPendingFrame();
    return 0;
  }
  return std::nullopt;
}

}  // namespace infravision_camera
