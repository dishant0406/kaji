#import "KajiCEFTextVisitor.h"

KajiCEFTextVisitor::KajiCEFTextVisitor(KajiCEFTextHandler completion)
    : completion_([completion copy]) {}

void KajiCEFTextVisitor::Visit(const CefString& string) {
  std::string value(string);
  NSString* text = [NSString stringWithUTF8String:value.c_str()] ?: @"";
  KajiCEFTextHandler completion = completion_;
  dispatch_async(dispatch_get_main_queue(), ^{
    completion(text);
  });
}
