#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^KajiCEFPageChangeHandler)(NSString *url, NSString *title);
typedef void (^KajiCEFPopupHandler)(NSString *url);
typedef void (^KajiCEFTextHandler)(NSString *text);

@interface KajiCEFRuntime : NSObject
+ (BOOL)startWithRootPath:(NSString *)rootPath profilePath:(NSString *)profilePath helperPath:(NSString *)helperPath error:(NSError **)error;
+ (BOOL)startWithRootPath:(NSString *)rootPath profilePath:(NSString *)profilePath helperPath:(NSString *)helperPath remoteDebuggingPort:(int)remoteDebuggingPort error:(NSError **)error;
+ (void)pumpMessageLoop;
@end

@interface KajiCEFBrowserView : NSView
@property(nonatomic, copy, nullable) KajiCEFPageChangeHandler pageChanged;
@property(nonatomic, copy, nullable) KajiCEFPopupHandler popupRequested;
- (instancetype)initWithURL:(NSString *)url;
- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reloadPage;
- (void)readPage:(KajiCEFTextHandler)completion;
- (void)showDevTools;
- (void)applyDeviceProfileWithWidth:(int)width height:(int)height deviceScaleFactor:(double)deviceScaleFactor userAgent:(NSString *)userAgent mobile:(BOOL)mobile touch:(BOOL)touch platform:(NSString *)platform;
- (void)clickSelector:(NSString *)selector;
- (void)typeText:(NSString *)text selector:(NSString *)selector;
- (void)setActive:(BOOL)active;
- (void)focusBrowser;
- (void)closeBrowser;
@end

NS_ASSUME_NONNULL_END
