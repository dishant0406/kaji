#import "KajiCEFBridge.h"
#import "KajiCEFClient.h"

#include "include/cef_browser.h"

@interface KajiCEFBrowserView ()
@property(nonatomic, copy) NSString* initialURL;
@end

@implementation KajiCEFBrowserView {
  CefRefPtr<KajiCEFClient> _client;
  BOOL _created;
  BOOL _closing;
}

- (instancetype)initWithURL:(NSString*)url {
  self = [super initWithFrame:NSZeroRect];
  if (!self) {
    return nil;
  }
  _initialURL = [url copy];
  self.wantsLayer = YES;
  self.layer.masksToBounds = YES;
  return self;
}

- (BOOL)acceptsFirstResponder { return YES; }

- (BOOL)becomeFirstResponder {
  [self focusBrowser];
  return YES;
}

- (void)focusBrowser {
  if (_closing) {
    return;
  }
  if (_client) {
    _client->SetHidden(NO);
  }
  if (self.window) {
    NSView* browserView = _client && _client->browser()
      ? CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(_client->browser()->GetHost()->GetWindowHandle())
      : nil;
    if (browserView && browserView != self) {
      [self.window makeFirstResponder:browserView];
    }
  }
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self createBrowserIfNeeded];
}

- (void)setFrameSize:(NSSize)newSize {
  [super setFrameSize:newSize];
  [self createBrowserIfNeeded];
  [self resizeBrowser];
}

- (void)layout {
  [super layout];
  [self createBrowserIfNeeded];
  [self resizeBrowser];
}

- (void)loadURL:(NSString*)url {
  if (!_client) {
    _initialURL = [url copy];
    [self createBrowserIfNeeded];
    return;
  }
  _client->LoadURL(url);
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)goBack {
  if (!_client) {
    return;
  }
  _client->GoBack();
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)goForward {
  if (!_client) {
    return;
  }
  _client->GoForward();
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)reloadPage {
  if (!_client) {
    return;
  }
  _client->Reload();
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)readPage:(KajiCEFTextHandler)completion {
  if (!_client) {
    completion(@"");
    return;
  }
  _client->ReadPage(completion);
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)showDevTools {
  if (!_client) {
    return;
  }
  _client->ShowDevTools();
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)applyDeviceProfileWithWidth:(int)width height:(int)height deviceScaleFactor:(double)deviceScaleFactor userAgent:(NSString*)userAgent mobile:(BOOL)mobile touch:(BOOL)touch platform:(NSString*)platform {
  if (!_client) {
    return;
  }
  _client->ApplyDeviceProfile(width, height, deviceScaleFactor, userAgent, mobile, touch, platform);
  [self resizeBrowser];
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)setActive:(BOOL)active {
  self.hidden = !active;
  if (_client) {
    _client->SetHidden(!active);
  }
}

- (void)closeBrowser {
  if (_closing) {
    return;
  }
  _closing = YES;
  if (_client) {
    _client->RetainUntilClose();
    _client->CloseBrowser();
    _client = nullptr;
  }
  self.pageChanged = nil;
  self.popupRequested = nil;
  _created = NO;
  if (self.superview) {
    [self removeFromSuperview];
  }
}

- (void)dealloc {
  [self closeBrowser];
}

- (void)clickSelector:(NSString*)selector {
  NSString* script = [NSString stringWithFormat:@"document.querySelector(%@)?.click()", [self json:selector]];
  if (!_client) {
    return;
  }
  _client->RunJavaScript(script);
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)typeText:(NSString*)text selector:(NSString*)selector {
  NSString* script = [NSString stringWithFormat:
    @"(()=>{const e=document.querySelector(%@);if(!e)return;e.focus();e.value=%@;e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));})()",
    [self json:selector], [self json:text]];
  if (!_client) {
    return;
  }
  _client->RunJavaScript(script);
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)createBrowserIfNeeded {
  if (_closing || _created || !self.window || self.bounds.size.width < 1 || self.bounds.size.height < 1) {
    return;
  }
  _created = YES;
  _client = new KajiCEFClient(self);
  CefWindowInfo windowInfo;
  CefRect rect(0, 0, static_cast<int>(self.bounds.size.width), static_cast<int>(self.bounds.size.height));
  windowInfo.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(self), rect);
  windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings browserSettings;
  CefBrowserHost::CreateBrowser(windowInfo, _client, std::string([_initialURL UTF8String]), browserSettings, nullptr, nullptr);
  [KajiCEFRuntime pumpMessageLoop];
}

- (void)resizeBrowser {
  if (!_client || !_client->browser()) {
    return;
  }
  NSView* browserView = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(_client->browser()->GetHost()->GetWindowHandle());
  browserView.frame = self.bounds;
}

- (NSString*)json:(NSString*)value {
  NSData* data = [NSJSONSerialization dataWithJSONObject:@[value ?: @""] options:0 error:nil];
  NSString* wrapped = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"[\"\"]";
  return [wrapped substringWithRange:NSMakeRange(1, wrapped.length - 2)];
}
@end
