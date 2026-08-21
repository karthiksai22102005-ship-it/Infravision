#ifndef FLUTTER_PLUGIN_INFRAVISION_CAMERA_PLUGIN_H_
#define FLUTTER_PLUGIN_INFRAVISION_CAMERA_PLUGIN_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void InfravisionCameraPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace infravision_camera {

// Custom window message to trigger sending the pending frame on the
// platform thread (required for platform channel message delivery).
constexpr UINT kFrameReadyMessage = WM_APP + 0x100;

class InfravisionCameraPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  InfravisionCameraPlugin(
      flutter::PluginRegistrarWindows* registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
          frame_channel);

  virtual ~InfravisionCameraPlugin();

  InfravisionCameraPlugin(const InfravisionCameraPlugin&) = delete;
  InfravisionCameraPlugin& operator=(const InfravisionCameraPlugin&) = delete;

  // Called from the capture thread to queue a frame and post a message
  // to the platform thread for delivery.
  void QueueFrame(const uint8_t* data, size_t length, int width, int height,
                  int64_t timestamp, const std::string& pixel_format);

 private:
  // Sends the latest queued frame on the platform thread (called from
  // the WindowProc delegate handler).
  void SendPendingFrame();

  // WindowProc delegate handler to receive WM_APP messages.
  std::optional<LRESULT> HandleWindowMessage(HWND hwnd, UINT message,
                                             WPARAM wparam, LPARAM lparam);

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleAvailableCameras(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleStartCamera(
      const std::string& device_id, int requested_width, int requested_height,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleStopCamera(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  class CameraSession;
  std::unique_ptr<CameraSession> session_;

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      frame_channel_;

  // Pending frame data, protected by mutex. Written on the capture thread,
  // read on the platform thread.
  std::mutex frame_mutex_;
  std::vector<uint8_t> pending_frame_;
  int pending_width_ = 0;
  int pending_height_ = 0;
  int64_t pending_timestamp_ = 0;
  std::string pending_pixel_format_ = "BGRA32";
  bool frame_pending_ = false;

  // ID of the registered WindowProc delegate.
  int window_proc_delegate_id_ = -1;
};

}  // namespace infravision_camera

#endif  // FLUTTER_PLUGIN_INFRAVISION_CAMERA_PLUGIN_H_
