#import <AppKit/AppKit.h>
#import "KajiCEFBridge.h"

#include "include/cef_client.h"
#include <string>

class KajiCEFClient : public CefClient,
                       public CefDisplayHandler,
                       public CefLifeSpanHandler,
                       public CefLoadHandler {
 public:
  explicit KajiCEFClient(KajiCEFBrowserView* owner);
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
  void ReadPage(KajiCEFTextHandler completion);
  void ShowDevTools();
  void ApplyDeviceProfile(int width, int height, double device_scale_factor, NSString* user_agent, bool mobile, bool touch, NSString* platform);
  void RunJavaScript(NSString* script);
  void SetHidden(bool hidden);
  void CloseBrowser();
  void RetainUntilClose();
  CefRefPtr<CefBrowser> browser() const;
 private:
  __weak KajiCEFBrowserView* owner_;
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefClient> devtools_client_;
  bool close_requested_ = false;
  std::string pending_url_;
  IMPLEMENT_REFCOUNTING(KajiCEFClient);
};
