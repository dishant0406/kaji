#import "DroidCEFMessagePump.h"

#import <AppKit/AppKit.h>
#include <algorithm>
#include <climits>
#include "include/cef_app.h"

static NSTimer* droidCEFPumpTimer = nil;
static bool droidCEFIsPumping = false;
static bool droidCEFNeedsPump = false;
static constexpr int64_t droidCEFMaxDelay = 1000 / 30;
static constexpr int64_t droidCEFPlaceholderDelay = INT_MAX;

static void droidCEFHandleSchedule(int64_t delay_ms);
static void droidCEFPerformWork();

static void droidCEFKillTimer() {
  [droidCEFPumpTimer invalidate];
  droidCEFPumpTimer = nil;
}

static bool droidCEFHasTimer() {
  return droidCEFPumpTimer != nil;
}

static void droidCEFSetTimer(int64_t delay_ms) {
  NSTimeInterval delay = static_cast<NSTimeInterval>(delay_ms) / 1000.0;
  droidCEFPumpTimer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(__unused NSTimer* timer) {
    droidCEFKillTimer();
    droidCEFPerformWork();
  }];
  NSRunLoop* runLoop = NSRunLoop.mainRunLoop;
  [runLoop addTimer:droidCEFPumpTimer forMode:NSRunLoopCommonModes];
  [runLoop addTimer:droidCEFPumpTimer forMode:NSEventTrackingRunLoopMode];
}

static void droidCEFDispatchSchedule(int64_t delay_ms) {
  dispatch_async(dispatch_get_main_queue(), ^{
    droidCEFHandleSchedule(delay_ms);
  });
}

static void droidCEFHandleSchedule(int64_t delay_ms) {
  if (delay_ms == droidCEFPlaceholderDelay && droidCEFHasTimer()) {
    return;
  }
  droidCEFKillTimer();
  if (delay_ms <= 0) {
    droidCEFPerformWork();
    return;
  }
  droidCEFSetTimer(std::min(delay_ms, droidCEFMaxDelay));
}

static void droidCEFPerformWork() {
  if (droidCEFIsPumping) {
    droidCEFNeedsPump = true;
    return;
  }
  droidCEFNeedsPump = false;
  droidCEFIsPumping = true;
  CefDoMessageLoopWork();
  droidCEFIsPumping = false;
  if (droidCEFNeedsPump) {
    droidCEFDispatchSchedule(0);
    return;
  }
  if (!droidCEFHasTimer()) {
    droidCEFDispatchSchedule(droidCEFPlaceholderDelay);
  }
}

void DroidCEFScheduleMessagePumpWork(int64_t delay_ms) {
  droidCEFDispatchSchedule(delay_ms);
}

void DroidCEFPumpMessageLoopNow() {
  droidCEFDispatchSchedule(0);
}
