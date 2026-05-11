#import "KajiCEFClient.h"
#import "KajiCEFTextVisitor.h"

#include "include/cef_values.h"
#include "include/wrapper/cef_helpers.h"
#include <algorithm>
#include <vector>

namespace {
std::vector<CefRefPtr<KajiCEFClient>> closing_clients;

void ReleaseClosingClient(KajiCEFClient* client) {
  closing_clients.erase(
      std::remove_if(closing_clients.begin(), closing_clients.end(), [client](const CefRefPtr<KajiCEFClient>& item) {
        return item.get() == client;
      }),
      closing_clients.end());
}
}

class KajiCEFDevToolsObserver : public CefDevToolsMessageObserver {
 public:
  explicit KajiCEFDevToolsObserver(KajiCEFClient* client) : client_(client) {}

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,
                              int message_id,
                              bool success,
                              const void* result,
                              size_t result_size) override {
    if (client_) {
      client_->CompleteDevToolsMethod(message_id, success, result, result_size);
    }
  }

 private:
  KajiCEFClient* client_;
  IMPLEMENT_REFCOUNTING(KajiCEFDevToolsObserver);
};

KajiCEFClient::KajiCEFClient(KajiCEFBrowserView* owner) : owner_(owner) {}

CefRefPtr<CefDisplayHandler> KajiCEFClient::GetDisplayHandler() { return this; }

CefRefPtr<CefLifeSpanHandler> KajiCEFClient::GetLifeSpanHandler() { return this; }

CefRefPtr<CefLoadHandler> KajiCEFClient::GetLoadHandler() { return this; }

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
  dispatch_async(dispatch_get_main_queue(), ^{
    if (owner.popupRequested) {
      owner.popupRequested(nsURL ?: @"about:blank");
    }
  });
  return true;
}

void KajiCEFClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  if (browser_.get() == browser.get()) {
    browser_ = nullptr;
  }
  pending_url_.clear();
  ReleaseClosingClient(this);
}

void KajiCEFClient::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) {
  CEF_REQUIRE_UI_THREAD();
  std::string titleValue(title);
  std::string urlValue = browser->GetMainFrame()->GetURL();
  NSString* nsTitle = [NSString stringWithUTF8String:titleValue.c_str()] ?: @"Browser";
  NSString* nsURL = [NSString stringWithUTF8String:urlValue.c_str()] ?: @"";
  KajiCEFBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
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
  dispatch_async(dispatch_get_main_queue(), ^{
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

void KajiCEFClient::EvaluateJavaScript(NSString* script, KajiCEFScriptHandler completion) {
  if (!browser_) {
    completion(@"Browser is not ready.");
    return;
  }
  if (!devtools_registration_) {
    devtools_registration_ = browser_->GetHost()->AddDevToolsMessageObserver(new KajiCEFDevToolsObserver(this));
  }
  CefRefPtr<CefDictionaryValue> params = CefDictionaryValue::Create();
  params->SetString("expression", std::string([script UTF8String]));
  params->SetBool("returnByValue", true);
  params->SetBool("awaitPromise", true);
  params->SetBool("userGesture", true);
  int message_id = browser_->GetHost()->ExecuteDevToolsMethod(++devtools_message_id_, "Runtime.evaluate", params);
  if (message_id == 0) {
    completion(@"JavaScript evaluation failed to start.");
    return;
  }
  pending_script_handlers_[message_id] = [completion copy];
}

void KajiCEFClient::CompleteDevToolsMethod(int message_id, bool success, const void* result, size_t result_size) {
  auto handler = pending_script_handlers_.find(message_id);
  if (handler == pending_script_handlers_.end()) {
    return;
  }
  KajiCEFScriptHandler completion = handler->second;
  pending_script_handlers_.erase(handler);
  NSString* output = FormatScriptResult(success, result, result_size);
  dispatch_async(dispatch_get_main_queue(), ^{
    completion(output ?: @"");
  });
}

NSString* KajiCEFClient::FormatScriptResult(bool success, const void* result, size_t result_size) {
  if (!result || result_size == 0) {
    return success ? @"undefined" : @"Evaluation failed.";
  }
  NSData* data = [NSData dataWithBytes:result length:result_size];
  NSDictionary* payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (!success) {
    NSString* message = payload[@"message"];
    return message.length > 0 ? message : @"Evaluation failed.";
  }
  NSDictionary* exception = payload[@"exceptionDetails"];
  if ([exception isKindOfClass:[NSDictionary class]]) {
    NSString* text = exception[@"text"];
    NSDictionary* details = exception[@"exception"];
    NSString* description = details[@"description"] ?: details[@"value"];
    return description.length > 0 ? description : (text.length > 0 ? text : @"Uncaught exception");
  }
  NSDictionary* remoteObject = payload[@"result"];
  id value = remoteObject[@"value"];
  if (!value || value == [NSNull null]) {
    NSString* description = remoteObject[@"description"];
    return description.length > 0 ? description : @"undefined";
  }
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  NSData* valueData = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil];
  return [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding] ?: [value description];
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
  for (auto& entry : pending_script_handlers_) {
    KajiCEFScriptHandler completion = entry.second;
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(@"Browser closed before JavaScript finished.");
    });
  }
  pending_script_handlers_.clear();
  devtools_registration_ = nullptr;
  if (!browser_) {
    return;
  }
  browser_->GetHost()->CloseBrowser(true);
  browser_ = nullptr;
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
