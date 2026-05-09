#import "DroidCEFClient.h"
#import "DroidCEFTextVisitor.h"

#include "include/wrapper/cef_helpers.h"

DroidCEFClient::DroidCEFClient(DroidCEFBrowserView* owner) : owner_(owner) {}

CefRefPtr<CefDisplayHandler> DroidCEFClient::GetDisplayHandler() { return this; }

CefRefPtr<CefLifeSpanHandler> DroidCEFClient::GetLifeSpanHandler() { return this; }

CefRefPtr<CefLoadHandler> DroidCEFClient::GetLoadHandler() { return this; }

void DroidCEFClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  browser_ = browser;
  if (!pending_url_.empty()) {
    browser_->GetMainFrame()->LoadURL(pending_url_);
    pending_url_.clear();
  }
}

bool DroidCEFClient::OnBeforePopup(CefRefPtr<CefBrowser> browser,
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
  DroidCEFBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (owner.popupRequested) {
      owner.popupRequested(nsURL ?: @"about:blank");
    }
  });
  return true;
}

void DroidCEFClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  if (browser_.get() == browser.get()) {
    browser_ = nullptr;
  }
  pending_url_.clear();
}

void DroidCEFClient::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) {
  CEF_REQUIRE_UI_THREAD();
  std::string titleValue(title);
  std::string urlValue = browser->GetMainFrame()->GetURL();
  NSString* nsTitle = [NSString stringWithUTF8String:titleValue.c_str()] ?: @"Browser";
  NSString* nsURL = [NSString stringWithUTF8String:urlValue.c_str()] ?: @"";
  DroidCEFBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (owner.pageChanged) {
      owner.pageChanged(nsURL, nsTitle);
    }
  });
}

void DroidCEFClient::OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) {
  CEF_REQUIRE_UI_THREAD();
  if (!frame->IsMain()) {
    return;
  }
  std::string urlValue(url);
  std::string titleValue = "Browser";
  NSString* nsURL = [NSString stringWithUTF8String:urlValue.c_str()] ?: @"";
  NSString* nsTitle = [NSString stringWithUTF8String:titleValue.c_str()] ?: @"Browser";
  DroidCEFBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (owner.pageChanged) {
      owner.pageChanged(nsURL, nsTitle);
    }
  });
}

void DroidCEFClient::LoadURL(NSString* url) {
  std::string urlValue([url UTF8String]);
  if (!browser_) {
    pending_url_ = urlValue;
    return;
  }
  browser_->GetMainFrame()->LoadURL(urlValue);
}

void DroidCEFClient::GoBack() {
  if (browser_) {
    browser_->GoBack();
  }
}

void DroidCEFClient::GoForward() {
  if (browser_) {
    browser_->GoForward();
  }
}

void DroidCEFClient::Reload() {
  if (browser_) {
    browser_->Reload();
  }
}

void DroidCEFClient::ReadPage(DroidCEFTextHandler completion) {
  if (!browser_) {
    completion(@"");
    return;
  }
  browser_->GetMainFrame()->GetText(new DroidCEFTextVisitor(completion));
}

void DroidCEFClient::RunJavaScript(NSString* script) {
  if (!browser_) {
    return;
  }
  std::string code([script UTF8String]);
  browser_->GetMainFrame()->ExecuteJavaScript(code, browser_->GetMainFrame()->GetURL(), 0);
}

void DroidCEFClient::SetHidden(bool hidden) {
  if (!browser_) {
    return;
  }
  browser_->GetHost()->WasHidden(hidden);
  browser_->GetHost()->SetFocus(!hidden);
}

void DroidCEFClient::CloseBrowser() {
  owner_ = nil;
  if (!browser_) {
    return;
  }
  browser_->GetHost()->CloseBrowser(true);
  browser_ = nullptr;
}

CefRefPtr<CefBrowser> DroidCEFClient::browser() const { return browser_; }
