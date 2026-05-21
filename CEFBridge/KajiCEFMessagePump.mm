#import "KajiCEFMessagePump.h"

#import <AppKit/AppKit.h>
#include <algorithm>
#include <climits>
#include <dispatch/dispatch.h>
#include "include/cef_app.h"

static NSTimer* kajiCEFPumpTimer = nil;
static dispatch_source_t kajiCEFAsyncPump = nil;
static bool kajiCEFIsPumping = false;
static bool kajiCEFNeedsPump = false;
static constexpr int64_t kajiCEFMaxDelay = 1000 / 30;
static constexpr int64_t kajiCEFPlaceholderDelay = INT_MAX;

static void kajiCEFHandleSchedule(int64_t delay_ms);
static void kajiCEFPerformWork();

static void kajiCEFKillTimer() {
  [kajiCEFPumpTimer invalidate];
  kajiCEFPumpTimer = nil;
}

static bool kajiCEFHasTimer() {
  return kajiCEFPumpTimer != nil;
}

static void kajiCEFSetTimer(int64_t delay_ms) {
  NSTimeInterval delay = static_cast<NSTimeInterval>(delay_ms) / 1000.0;
  kajiCEFPumpTimer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(__unused NSTimer* timer) {
    kajiCEFKillTimer();
    kajiCEFPerformWork();
  }];
  NSRunLoop* runLoop = NSRunLoop.mainRunLoop;
  [runLoop addTimer:kajiCEFPumpTimer forMode:NSRunLoopCommonModes];
  [runLoop addTimer:kajiCEFPumpTimer forMode:NSEventTrackingRunLoopMode];
}

static void kajiCEFDispatchPerformWork() {
  if (kajiCEFAsyncPump) {
    dispatch_source_merge_data(kajiCEFAsyncPump, 1);
    return;
  }
  kajiCEFAsyncPump = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_OR, 0, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(kajiCEFAsyncPump, ^{
    kajiCEFPerformWork();
  });
  dispatch_resume(kajiCEFAsyncPump);
  dispatch_source_merge_data(kajiCEFAsyncPump, 1);
}

static void kajiCEFDispatchSchedule(int64_t delay_ms) {
  dispatch_async(dispatch_get_main_queue(), ^{
    kajiCEFHandleSchedule(delay_ms);
  });
}

static void kajiCEFHandleSchedule(int64_t delay_ms) {
  if (delay_ms == kajiCEFPlaceholderDelay && kajiCEFHasTimer()) {
    return;
  }
  kajiCEFKillTimer();
  if (delay_ms <= 0) {
    kajiCEFDispatchPerformWork();
    return;
  }
  kajiCEFSetTimer(std::min(delay_ms, kajiCEFMaxDelay));
}

static void kajiCEFPerformWork() {
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
    return;
  }
  if (!kajiCEFHasTimer()) {
    kajiCEFDispatchSchedule(kajiCEFPlaceholderDelay);
  }
}

void KajiCEFScheduleMessagePumpWork(int64_t delay_ms) {
  kajiCEFDispatchSchedule(delay_ms);
}

void KajiCEFPumpMessageLoopNow() {
  kajiCEFDispatchSchedule(0);
}
