#import "KajiCEFBridge.h"
#import "KajiCEFApp.h"
#import "KajiCEFMessagePump.h"

#import <objc/runtime.h>
#import <crt_externs.h>

#include "include/cef_application_mac.h"
#include "include/wrapper/cef_library_loader.h"
static BOOL kajiCEFHandlingSendEvent = NO;
static BOOL kajiCEFStarted = NO;
static BOOL kajiCEFLibraryLoaded = NO;
static BOOL kajiCEFShutdown = NO;

@interface KajiCEFApplication : NSApplication <CefAppProtocol>
@end

@implementation KajiCEFApplication
- (BOOL)isHandlingSendEvent { return kajiCEFHandlingSendEvent; }
- (void)setHandlingSendEvent:(BOOL)value { kajiCEFHandlingSendEvent = value; }
- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent scopedEvent;
  [super sendEvent:event];
}
@end

@implementation KajiCEFRuntime
+ (void)pumpMessageLoop {
  if (!kajiCEFStarted) {
    return;
  }
  KajiCEFPumpMessageLoopNow();
}

+ (BOOL)startWithRootPath:(NSString*)rootPath profilePath:(NSString*)profilePath helperPath:(NSString*)helperPath error:(NSError**)error {
  return [self startWithRootPath:rootPath profilePath:profilePath rootCachePath:profilePath helperPath:helperPath remoteDebuggingPort:0 error:error];
}

+ (BOOL)startWithRootPath:(NSString*)rootPath profilePath:(NSString*)profilePath helperPath:(NSString*)helperPath remoteDebuggingPort:(int)remoteDebuggingPort error:(NSError**)error {
  return [self startWithRootPath:rootPath profilePath:profilePath rootCachePath:profilePath helperPath:helperPath remoteDebuggingPort:remoteDebuggingPort error:error];
}

+ (BOOL)startWithRootPath:(NSString*)rootPath profilePath:(NSString*)profilePath rootCachePath:(NSString*)rootCachePath helperPath:(NSString*)helperPath remoteDebuggingPort:(int)remoteDebuggingPort error:(NSError**)error {
  if (kajiCEFShutdown) {
    [self assignError:error message:@"CEF has already shut down for this process."];
    return NO;
  }
  if (kajiCEFStarted) {
    return YES;
  }
  if (![[NSFileManager defaultManager] fileExistsAtPath:rootPath]) {
    [self assignError:error message:@"CEF runtime is missing."];
    return NO;
  }
  if (![self loadLibraryAtRootPath:rootPath error:error]) {
    return NO;
  }
  KajiCEFResetMessagePump();
  CefMainArgs mainArgs(*_NSGetArgc(), *_NSGetArgv());
  CefSettings settings;
  settings.no_sandbox = true;
  settings.external_message_pump = true;
  NSString* frameworkDirectory = [self frameworkDirectoryPathAtRootPath:rootPath];
  NSString* resourcesPath = [frameworkDirectory stringByAppendingPathComponent:@"Resources"];
  NSString* mainBundlePath = [self mainBundlePathForRootPath:rootPath];
  NSString* logPath = [self logPathForProfilePath:profilePath];
  CefString(&settings.cache_path).FromString(std::string([profilePath UTF8String]));
  CefString(&settings.root_cache_path).FromString(std::string([rootCachePath UTF8String]));
  CefString(&settings.log_file).FromString(std::string([logPath UTF8String]));
  settings.log_severity = LOGSEVERITY_INFO;
  CefString(&settings.browser_subprocess_path).FromString(std::string([helperPath UTF8String]));
  CefString(&settings.framework_dir_path).FromString(std::string([frameworkDirectory UTF8String]));
  CefString(&settings.main_bundle_path).FromString(std::string([mainBundlePath UTF8String]));
  CefString(&settings.resources_dir_path).FromString(std::string([resourcesPath UTF8String]));
  CefString(&settings.locales_dir_path).FromString(std::string([resourcesPath UTF8String]));
  if (remoteDebuggingPort > 0) {
    settings.remote_debugging_port = remoteDebuggingPort;
  }
  CefRefPtr<KajiCEFApp> app(new KajiCEFApp());
  if (!CefInitialize(mainArgs, settings, app.get(), nullptr)) {
    [self assignError:error message:@"CEF initialization failed."];
    return NO;
  }
  NSLog(@"Kaji CEF started root=%@ profile=%@ rootCache=%@ helper=%@ debugPort=%d", rootPath, profilePath, rootCachePath, helperPath, remoteDebuggingPort);
  [self installApplicationHooks];
  kajiCEFStarted = YES;
  KajiCEFPumpMessageLoopNow();
  return YES;
}

+ (void)shutdown {
  if (!kajiCEFStarted || kajiCEFShutdown) {
    return;
  }
  [self drainMessageLoopBeforeShutdown];
  KajiCEFCancelMessagePump();
  CefShutdown();
  kajiCEFStarted = NO;
  kajiCEFShutdown = YES;
  NSLog(@"Kaji CEF shut down");
}

+ (void)drainMessageLoopBeforeShutdown {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
  while ([deadline timeIntervalSinceNow] > 0) {
    CefDoMessageLoopWork();
    [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
}

+ (void)installApplicationHooks {
  NSApplication* application = [NSApplication sharedApplication];
  if ([application isKindOfClass:[KajiCEFApplication class]]) {
    return;
  }
  object_setClass(application, [KajiCEFApplication class]);
}

+ (BOOL)loadLibraryAtRootPath:(NSString*)rootPath error:(NSError**)error {
  if (kajiCEFLibraryLoaded) {
    return YES;
  }
  NSString* frameworkPath = [[self frameworkDirectoryPathAtRootPath:rootPath] stringByAppendingPathComponent:@"Chromium Embedded Framework"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:frameworkPath]) {
    [self assignError:error message:@"CEF framework binary is missing."];
    return NO;
  }
  if (!cef_load_library([frameworkPath fileSystemRepresentation])) {
    [self assignError:error message:@"CEF framework failed to load."];
    return NO;
  }
  kajiCEFLibraryLoaded = YES;
  return YES;
}

+ (NSString*)frameworkDirectoryPathAtRootPath:(NSString*)rootPath {
  NSString* direct = [rootPath stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:direct]) {
    return direct;
  }
  return [rootPath stringByAppendingPathComponent:@"Release/Chromium Embedded Framework.framework"];
}

+ (NSString*)mainBundlePathForRootPath:(NSString*)rootPath {
  NSString* bundlePath = [NSBundle mainBundle].bundlePath;
  if ([bundlePath.pathExtension isEqualToString:@"app"]) {
    return bundlePath;
  }
  return [rootPath stringByAppendingPathComponent:@"../build/tests/cefsimple/Release/cefsimple.app"].stringByStandardizingPath;
}

+ (NSString*)logPathForProfilePath:(NSString*)profilePath {
  NSString* directory = [profilePath stringByAppendingPathComponent:@"Logs"];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
  return [directory stringByAppendingPathComponent:@"cef.log"];
}

+ (void)assignError:(NSError**)error message:(NSString*)message {
  if (!error) {
    return;
  }
  *error = [NSError errorWithDomain:@"KajiCEF" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}
@end
