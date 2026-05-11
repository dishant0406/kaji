#import "KajiCEFBridge.h"

#include "include/cef_string_visitor.h"

class KajiCEFTextVisitor : public CefStringVisitor {
 public:
  explicit KajiCEFTextVisitor(KajiCEFTextHandler completion);
  void Visit(const CefString& string) override;
 private:
  KajiCEFTextHandler completion_;
  IMPLEMENT_REFCOUNTING(KajiCEFTextVisitor);
};
