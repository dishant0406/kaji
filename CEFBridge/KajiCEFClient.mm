#import "KajiCEFClient.h"
#import "KajiCEFTextVisitor.h"

#include "include/cef_values.h"
#include "include/wrapper/cef_helpers.h"
#include <algorithm>
#include <vector>

namespace {
std::vector<CefRefPtr<KajiCEFClient>> closing_clients;

void DispatchToMain(void (^block)(void)) {
  if ([NSThread isMainThread]) {
    block();
    return;
  }
  dispatch_async(dispatch_get_main_queue(), block);
}

void ReleaseClosingClient(KajiCEFClient* client) {
  closing_clients.erase(
      std::remove_if(closing_clients.begin(), closing_clients.end(), [client](const CefRefPtr<KajiCEFClient>& item) {
        return item.get() == client;
      }),
      closing_clients.end());
}
}

class KajiCEFDevToolsClient : public CefClient, public CefLifeSpanHandler {
 public:
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browser_ = browser;
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    browser_ = nullptr;
  }

  CefRefPtr<CefBrowser> browser() const { return browser_; }

 private:
  CefRefPtr<CefBrowser> browser_;
  IMPLEMENT_REFCOUNTING(KajiCEFDevToolsClient);
};

KajiCEFClient::KajiCEFClient(KajiCEFBrowserView* owner) : owner_(owner) {}

CefRefPtr<CefDisplayHandler> KajiCEFClient::GetDisplayHandler() { return this; }

CefRefPtr<CefLifeSpanHandler> KajiCEFClient::GetLifeSpanHandler() { return this; }

CefRefPtr<CefLoadHandler> KajiCEFClient::GetLoadHandler() { return this; }

CefRefPtr<CefRequestHandler> KajiCEFClient::GetRequestHandler() { return this; }

void KajiCEFClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  browser_ = browser;
  if (close_requested_ || !owner_) {
    browser_->GetHost()->CloseBrowser(true);
    browser_ = nullptr;
    pending_url_.clear();
    return;
  }
  if (!pending_url_.empty()) {
    browser_->GetMainFrame()->LoadURL(pending_url_);
    pending_url_.clear();
  }
}

bool KajiCEFClient::DoClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  return false;
}

bool KajiCEFClient::OnBeforePopup(CefRefPtr<CefBrowser> browser,
                                   CefRefPtr<CefFrame> frame,
                                   int popup_id,
                                   const CefString& target_url,
                                   const CefString& target_frame_name,
                                   WindowOpenDisposition target_disposition,
                                   bool user_gesture,
                                   const CefPopupFeatures& popupFeatures,
                                   CefWindowInfo& windowInfo,
                                   CefRefPtr<CefClient>& client,
                                   CefBrowserSettings& settings,
                                   CefRefPtr<CefDictionaryValue>& extra_info,
                                   bool* no_javascript_access) {
  CEF_REQUIRE_UI_THREAD();
  std::string urlValue(target_url);
  NSString* nsURL = urlValue.empty() ? @"about:blank" : [NSString stringWithUTF8String:urlValue.c_str()];
  KajiCEFBrowserView* owner = owner_;
  DispatchToMain(^{
    if (owner.popupRequested) {
      owner.popupRequested(nsURL ?: @"about:blank");
    }
  });
  return true;
}

void KajiCEFClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  NSLog(@"Kaji CEF browser before close id=%d", browser->GetIdentifier());
  if (browser_.get() == browser.get()) {
    browser_ = nullptr;
  }
  pending_url_.clear();
  ReleaseClosingClient(this);
}

void KajiCEFClient::OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser, TerminationStatus status, int error_code, const CefString& error_string) {
  CEF_REQUIRE_UI_THREAD();
  std::string value(error_string);
  NSString* reason = [NSString stringWithUTF8String:value.c_str()] ?: @"";
  NSLog(@"Kaji CEF render process terminated id=%d status=%d error=%d reason=%@", browser->GetIdentifier(), status, error_code, reason);
}

void KajiCEFClient::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) {
  CEF_REQUIRE_UI_THREAD();
  std::string titleValue(title);
  std::string urlValue = browser->GetMainFrame()->GetURL();
  NSString* nsTitle = [NSString stringWithUTF8String:titleValue.c_str()] ?: @"Browser";
  NSString* nsURL = [NSString stringWithUTF8String:urlValue.c_str()] ?: @"";
  KajiCEFBrowserView* owner = owner_;
  DispatchToMain(^{
    if (owner.pageChanged) {
      owner.pageChanged(nsURL, nsTitle);
    }
  });
}

void KajiCEFClient::OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) {
  CEF_REQUIRE_UI_THREAD();
  if (!frame->IsMain()) {
    return;
  }
  std::string urlValue(url);
  std::string titleValue = "Browser";
  NSString* nsURL = [NSString stringWithUTF8String:urlValue.c_str()] ?: @"";
  NSString* nsTitle = [NSString stringWithUTF8String:titleValue.c_str()] ?: @"Browser";
  KajiCEFBrowserView* owner = owner_;
  DispatchToMain(^{
    if (owner.pageChanged) {
      owner.pageChanged(nsURL, nsTitle);
    }
  });
}

void KajiCEFClient::LoadURL(NSString* url) {
  std::string urlValue([url UTF8String]);
  if (!browser_) {
    pending_url_ = urlValue;
    return;
  }
  browser_->GetMainFrame()->LoadURL(urlValue);
}

void KajiCEFClient::GoBack() {
  if (browser_) {
    browser_->GoBack();
  }
}

void KajiCEFClient::GoForward() {
  if (browser_) {
    browser_->GoForward();
  }
}

void KajiCEFClient::Reload() {
  if (browser_) {
    browser_->Reload();
  }
}

void KajiCEFClient::ReadPage(KajiCEFTextHandler completion) {
  if (!browser_) {
    completion(@"");
    return;
  }
  browser_->GetMainFrame()->GetText(new KajiCEFTextVisitor(completion));
}

void KajiCEFClient::ShowDevTools() {
  if (!browser_) {
    return;
  }
  if (browser_->GetHost()->HasDevTools()) {
    browser_->GetHost()->CloseDevTools();
  }
  CefWindowInfo windowInfo;
  CefBrowserSettings settings;
  devtools_client_ = new KajiCEFDevToolsClient();
  browser_->GetHost()->ShowDevTools(windowInfo, devtools_client_, settings, CefPoint());
}

void KajiCEFClient::RunJavaScript(NSString* script) {
  if (!browser_) {
    return;
  }
  std::string code([script UTF8String]);
  browser_->GetMainFrame()->ExecuteJavaScript(code, browser_->GetMainFrame()->GetURL(), 0);
}

void KajiCEFClient::ApplyDeviceProfile(int width, int height, double device_scale_factor, NSString* user_agent, bool mobile, bool touch, NSString* platform) {
  if (!browser_) {
    return;
  }
  if (width <= 0 || height <= 0) {
    browser_->GetHost()->ExecuteDevToolsMethod(0, "Emulation.clearDeviceMetricsOverride", CefDictionaryValue::Create());
    browser_->GetHost()->ExecuteDevToolsMethod(0, "Emulation.clearTouchEmulationConfiguration", CefDictionaryValue::Create());
    browser_->GetHost()->ExecuteDevToolsMethod(0, "Emulation.setUserAgentOverride", CefDictionaryValue::Create());
    return;
  }
  CefRefPtr<CefDictionaryValue> metrics = CefDictionaryValue::Create();
  metrics->SetInt("width", width);
  metrics->SetInt("height", height);
  metrics->SetDouble("deviceScaleFactor", device_scale_factor);
  metrics->SetBool("mobile", mobile);
  browser_->GetHost()->ExecuteDevToolsMethod(0, "Emulation.setDeviceMetricsOverride", metrics);

  CefRefPtr<CefDictionaryValue> touchParams = CefDictionaryValue::Create();
  touchParams->SetBool("enabled", touch);
  browser_->GetHost()->ExecuteDevToolsMethod(0, "Emulation.setTouchEmulationEnabled", touchParams);

  CefRefPtr<CefDictionaryValue> userAgentParams = CefDictionaryValue::Create();
  userAgentParams->SetString("userAgent", std::string([user_agent UTF8String]));
  userAgentParams->SetString("platform", std::string([platform UTF8String]));
  browser_->GetHost()->ExecuteDevToolsMethod(0, "Emulation.setUserAgentOverride", userAgentParams);
}

void KajiCEFClient::SetHidden(bool hidden) {
  if (!browser_) {
    return;
  }
  browser_->GetHost()->WasHidden(hidden);
  browser_->GetHost()->SetFocus(!hidden);
}

void KajiCEFClient::CloseBrowser() {
  owner_ = nil;
  close_requested_ = true;
  if (!browser_) {
    return;
  }
  browser_->GetHost()->CloseDevTools();
  devtools_client_ = nullptr;
  browser_->GetHost()->CloseBrowser(false);
}

void KajiCEFClient::RetainUntilClose() {
  auto found = std::find_if(closing_clients.begin(), closing_clients.end(), [this](const CefRefPtr<KajiCEFClient>& item) {
    return item.get() == this;
  });
  if (found == closing_clients.end()) {
    closing_clients.push_back(this);
  }
}

CefRefPtr<CefBrowser> KajiCEFClient::browser() const { return browser_; }
