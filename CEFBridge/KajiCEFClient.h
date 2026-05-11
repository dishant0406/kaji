#import <AppKit/AppKit.h>
#import "KajiCEFBridge.h"

#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include <string>
#include <unordered_map>

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
  void EvaluateJavaScript(NSString* script, KajiCEFScriptHandler completion);
  void ApplyDeviceProfile(int width, int height, double device_scale_factor, NSString* user_agent, bool mobile, bool touch, NSString* platform);
  void RunJavaScript(NSString* script);
  void SetHidden(bool hidden);
  void CloseBrowser();
  void RetainUntilClose();
  CefRefPtr<CefBrowser> browser() const;
  void CompleteDevToolsMethod(int message_id, bool success, const void* result, size_t result_size);
 private:
  NSString* FormatScriptResult(bool success, const void* result, size_t result_size);
  __weak KajiCEFBrowserView* owner_;
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefRegistration> devtools_registration_;
  int devtools_message_id_ = 0;
  bool close_requested_ = false;
  std::string pending_url_;
  std::unordered_map<int, KajiCEFScriptHandler> pending_script_handlers_;
  IMPLEMENT_REFCOUNTING(KajiCEFClient);
};
