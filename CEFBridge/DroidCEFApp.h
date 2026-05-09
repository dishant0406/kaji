#include "include/cef_app.h"
#include "include/cef_browser_process_handler.h"
#include "include/cef_command_line.h"

class DroidCEFApp : public CefApp, public CefBrowserProcessHandler {
 public:
  DroidCEFApp();
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override;
  void OnBeforeCommandLineProcessing(
      const CefString& process_type,
      CefRefPtr<CefCommandLine> command_line) override;
  void OnScheduleMessagePumpWork(int64_t delay_ms) override;
 private:
  IMPLEMENT_REFCOUNTING(DroidCEFApp);
};
