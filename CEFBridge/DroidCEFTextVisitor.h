#import "DroidCEFBridge.h"

#include "include/cef_string_visitor.h"

class DroidCEFTextVisitor : public CefStringVisitor {
 public:
  explicit DroidCEFTextVisitor(DroidCEFTextHandler completion);
  void Visit(const CefString& string) override;
 private:
  DroidCEFTextHandler completion_;
  IMPLEMENT_REFCOUNTING(DroidCEFTextVisitor);
};
