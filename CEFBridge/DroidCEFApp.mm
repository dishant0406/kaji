#import "DroidCEFApp.h"
#import "DroidCEFMessagePump.h"

DroidCEFApp::DroidCEFApp() = default;

CefRefPtr<CefBrowserProcessHandler> DroidCEFApp::GetBrowserProcessHandler() {
  return this;
}

void DroidCEFApp::OnBeforeCommandLineProcessing(
    const CefString& process_type,
    CefRefPtr<CefCommandLine> command_line) {
  command_line->AppendSwitch("use-mock-keychain");
  command_line->AppendSwitch("disable-chrome-login-prompt");
}

void DroidCEFApp::OnScheduleMessagePumpWork(int64_t delay_ms) {
  DroidCEFScheduleMessagePumpWork(delay_ms);
}
