#import <AppKit/AppKit.h>
#import "DroidCEFBridge.h"

#include "include/cef_client.h"
#include <string>

class DroidCEFClient : public CefClient,
                       public CefDisplayHandler,
                       public CefLifeSpanHandler,
                       public CefLoadHandler {
 public:
  explicit DroidCEFClient(DroidCEFBrowserView* owner);
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override;
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override;
  CefRefPtr<CefLoadHandler> GetLoadHandler() override;
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
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
                     bool* no_javascript_access) override;
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;
  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override;
  void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) override;
  void LoadURL(NSString* url);
  void GoBack();
  void GoForward();
  void Reload();
  void ReadPage(DroidCEFTextHandler completion);
  void RunJavaScript(NSString* script);
  void SetHidden(bool hidden);
  void CloseBrowser();
  CefRefPtr<CefBrowser> browser() const;
 private:
  __weak DroidCEFBrowserView* owner_;
  CefRefPtr<CefBrowser> browser_;
  std::string pending_url_;
  IMPLEMENT_REFCOUNTING(DroidCEFClient);
};
