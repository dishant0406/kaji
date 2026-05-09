#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^DroidCEFPageChangeHandler)(NSString *url, NSString *title);
typedef void (^DroidCEFPopupHandler)(NSString *url);
typedef void (^DroidCEFTextHandler)(NSString *text);

@interface DroidCEFRuntime : NSObject
+ (BOOL)startWithRootPath:(NSString *)rootPath profilePath:(NSString *)profilePath helperPath:(NSString *)helperPath error:(NSError **)error;
+ (void)pumpMessageLoop;
@end

@interface DroidCEFBrowserView : NSView
@property(nonatomic, copy, nullable) DroidCEFPageChangeHandler pageChanged;
@property(nonatomic, copy, nullable) DroidCEFPopupHandler popupRequested;
- (instancetype)initWithURL:(NSString *)url;
- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reloadPage;
- (void)readPage:(DroidCEFTextHandler)completion;
- (void)clickSelector:(NSString *)selector;
- (void)typeText:(NSString *)text selector:(NSString *)selector;
- (void)setActive:(BOOL)active;
- (void)focusBrowser;
- (void)closeBrowser;
@end

NS_ASSUME_NONNULL_END
