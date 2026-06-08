#import "KajiCEFMessagePump.h"

#import <AppKit/AppKit.h>
#include <algorithm>
#include <dispatch/dispatch.h>
#include "include/cef_app.h"

static dispatch_source_t kajiCEFDelayedPump = nil;
static bool kajiCEFImmediatePumpPending = false;
static bool kajiCEFIsPumping = false;
static bool kajiCEFNeedsPump = false;
static bool kajiCEFIsShuttingDown = false;

static void kajiCEFHandleSchedule(int64_t delay_ms);
static void kajiCEFPerformWork();
static void kajiCEFCancelMessagePumpOnMain();

static void kajiCEFCancelDelayedPump() {
  if (!kajiCEFDelayedPump) {
    return;
  }
  dispatch_source_cancel(kajiCEFDelayedPump);
  kajiCEFDelayedPump = nil;
}

static void kajiCEFDispatchPerformWork() {
  if (kajiCEFIsShuttingDown || kajiCEFImmediatePumpPending) {
    return;
  }
  kajiCEFImmediatePumpPending = true;
  dispatch_async(dispatch_get_main_queue(), ^{
    kajiCEFImmediatePumpPending = false;
    kajiCEFPerformWork();
  });
}

static void kajiCEFSetDelayedPump(int64_t delay_ms) {
  kajiCEFCancelDelayedPump();
  if (kajiCEFIsShuttingDown) {
    return;
  }
  uint64_t delay = static_cast<uint64_t>(delay_ms) * NSEC_PER_MSEC;
  uint64_t leeway = std::min<uint64_t>(delay / 10, 5 * NSEC_PER_MSEC);
  kajiCEFDelayedPump = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
  dispatch_source_set_timer(kajiCEFDelayedPump, dispatch_time(DISPATCH_TIME_NOW, delay), DISPATCH_TIME_FOREVER, leeway);
  dispatch_source_set_event_handler(kajiCEFDelayedPump, ^{
    kajiCEFCancelDelayedPump();
    kajiCEFPerformWork();
  });
  dispatch_resume(kajiCEFDelayedPump);
}

static void kajiCEFDispatchSchedule(int64_t delay_ms) {
  dispatch_async(dispatch_get_main_queue(), ^{
    kajiCEFHandleSchedule(delay_ms);
  });
}

static void kajiCEFHandleSchedule(int64_t delay_ms) {
  if (kajiCEFIsShuttingDown) {
    return;
  }
  kajiCEFCancelDelayedPump();
  if (delay_ms <= 0) {
    kajiCEFDispatchPerformWork();
    return;
  }
  kajiCEFSetDelayedPump(delay_ms);
}

static void kajiCEFPerformWork() {
  if (![NSThread isMainThread]) {
    kajiCEFDispatchPerformWork();
    return;
  }
  if (kajiCEFIsPumping) {
    kajiCEFNeedsPump = true;
    return;
  }
  kajiCEFNeedsPump = false;
  kajiCEFIsPumping = true;
  CefDoMessageLoopWork();
  kajiCEFIsPumping = false;
  if (kajiCEFNeedsPump) {
    kajiCEFDispatchSchedule(0);
  }
}

void KajiCEFScheduleMessagePumpWork(int64_t delay_ms) {
  if (kajiCEFIsShuttingDown) {
    return;
  }
  kajiCEFDispatchSchedule(delay_ms);
}

void KajiCEFPumpMessageLoopNow() {
  if (kajiCEFIsShuttingDown) {
    return;
  }
  kajiCEFDispatchSchedule(0);
}

static void kajiCEFCancelMessagePumpOnMain() {
  kajiCEFIsShuttingDown = true;
  kajiCEFCancelDelayedPump();
  kajiCEFImmediatePumpPending = false;
  kajiCEFNeedsPump = false;
}

void KajiCEFCancelMessagePump() {
  if ([NSThread isMainThread]) {
    kajiCEFCancelMessagePumpOnMain();
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    kajiCEFCancelMessagePumpOnMain();
  });
}

void KajiCEFResetMessagePump() {
  if ([NSThread isMainThread]) {
    kajiCEFIsShuttingDown = false;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    kajiCEFIsShuttingDown = false;
  });
}
