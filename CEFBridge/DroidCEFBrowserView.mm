#import "DroidCEFBridge.h"
#import "DroidCEFClient.h"

#include "include/cef_browser.h"

@interface DroidCEFBrowserView ()
@property(nonatomic, copy) NSString* initialURL;
@end

@implementation DroidCEFBrowserView {
  CefRefPtr<DroidCEFClient> _client;
  BOOL _created;
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
  [DroidCEFRuntime pumpMessageLoop];
}

- (void)goBack {
  if (!_client) {
    return;
  }
  _client->GoBack();
  [DroidCEFRuntime pumpMessageLoop];
}

- (void)goForward {
  if (!_client) {
    return;
  }
  _client->GoForward();
  [DroidCEFRuntime pumpMessageLoop];
}

- (void)reloadPage {
  if (!_client) {
    return;
  }
  _client->Reload();
  [DroidCEFRuntime pumpMessageLoop];
}

- (void)readPage:(DroidCEFTextHandler)completion {
  if (!_client) {
    completion(@"");
    return;
  }
  _client->ReadPage(completion);
  [DroidCEFRuntime pumpMessageLoop];
}
- (void)setActive:(BOOL)active {
  self.hidden = !active;
  if (_client) {
    _client->SetHidden(!active);
  }
}

- (void)closeBrowser {
  if (_client) {
    _client->CloseBrowser();
    _client = nullptr;
  }
  _created = NO;
  [self removeFromSuperview];
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
  [DroidCEFRuntime pumpMessageLoop];
}

- (void)typeText:(NSString*)text selector:(NSString*)selector {
  NSString* script = [NSString stringWithFormat:
    @"(()=>{const e=document.querySelector(%@);if(!e)return;e.focus();e.value=%@;e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));})()",
    [self json:selector], [self json:text]];
  if (!_client) {
    return;
  }
  _client->RunJavaScript(script);
  [DroidCEFRuntime pumpMessageLoop];
}

- (void)createBrowserIfNeeded {
  if (_created || !self.window || self.bounds.size.width < 1 || self.bounds.size.height < 1) {
    return;
  }
  _created = YES;
  _client = new DroidCEFClient(self);
  CefWindowInfo windowInfo;
  CefRect rect(0, 0, static_cast<int>(self.bounds.size.width), static_cast<int>(self.bounds.size.height));
  windowInfo.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(self), rect);
  windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings browserSettings;
  CefBrowserHost::CreateBrowser(windowInfo, _client, std::string([_initialURL UTF8String]), browserSettings, nullptr, nullptr);
  [DroidCEFRuntime pumpMessageLoop];
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
