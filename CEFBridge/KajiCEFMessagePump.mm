#import "KajiCEFMessagePump.h"

#import <AppKit/AppKit.h>
#include <algorithm>
#include <climits>
#include "include/cef_app.h"

static NSTimer* kajiCEFPumpTimer = nil;
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
    kajiCEFPerformWork();
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
