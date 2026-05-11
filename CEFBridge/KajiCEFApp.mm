#import "KajiCEFApp.h"
#import "KajiCEFMessagePump.h"

KajiCEFApp::KajiCEFApp() = default;

CefRefPtr<CefBrowserProcessHandler> KajiCEFApp::GetBrowserProcessHandler() {
  return this;
}

void KajiCEFApp::OnBeforeCommandLineProcessing(
    const CefString& process_type,
    CefRefPtr<CefCommandLine> command_line) {
  command_line->AppendSwitch("use-mock-keychain");
  command_line->AppendSwitch("disable-chrome-login-prompt");
}

void KajiCEFApp::OnScheduleMessagePumpWork(int64_t delay_ms) {
  KajiCEFScheduleMessagePumpWork(delay_ms);
}
