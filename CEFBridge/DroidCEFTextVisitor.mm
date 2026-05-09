#import "DroidCEFTextVisitor.h"

DroidCEFTextVisitor::DroidCEFTextVisitor(DroidCEFTextHandler completion)
    : completion_([completion copy]) {}

void DroidCEFTextVisitor::Visit(const CefString& string) {
  std::string value(string);
  NSString* text = [NSString stringWithUTF8String:value.c_str()] ?: @"";
  DroidCEFTextHandler completion = completion_;
  dispatch_async(dispatch_get_main_queue(), ^{
    completion(text);
  });
}
