#import "KajiCEFApp.h"
#import "KajiCEFMessagePump.h"

#import <Foundation/Foundation.h>

KajiCEFApp::KajiCEFApp() = default;

CefRefPtr<CefBrowserProcessHandler> KajiCEFApp::GetBrowserProcessHandler() {
  return this;
}

void KajiCEFApp::OnBeforeCommandLineProcessing(
    const CefString& process_type,
    CefRefPtr<CefCommandLine> command_line) {
  command_line->AppendSwitch("use-mock-keychain");
  command_line->AppendSwitch("disable-chrome-login-prompt");
  command_line->AppendSwitch("disable-background-networking");
  command_line->AppendSwitch("disable-component-update");
  command_line->AppendSwitch("disable-domain-reliability");
  command_line->AppendSwitch("disable-extensions");
  command_line->AppendSwitch("disable-gpu-shader-disk-cache");
  command_line->AppendSwitch("disable-sync");
  command_line->AppendSwitch("disable-notifications");
  command_line->AppendSwitch("disable-component-extensions-with-background-pages");
  command_line->AppendSwitch("no-default-browser-check");
  command_line->AppendSwitch("no-first-run");
  command_line->AppendSwitchWithValue("disable-features", "AutofillServerCommunication,GCM,MediaRouter,OptimizationHints,OptimizationGuideModelExecution,TranslateUI");
}

bool KajiCEFApp::OnAlreadyRunningAppRelaunch(
    CefRefPtr<CefCommandLine> command_line,
    const CefString& current_directory) {
  NSLog(@"Kaji CEF ignored duplicate root-cache relaunch request");
  return true;
}

void KajiCEFApp::OnScheduleMessagePumpWork(int64_t delay_ms) {
  KajiCEFScheduleMessagePumpWork(delay_ms);
}
