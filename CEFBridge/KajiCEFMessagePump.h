#pragma once

#include <stdint.h>

void KajiCEFScheduleMessagePumpWork(int64_t delay_ms);
void KajiCEFPumpMessageLoopNow();
void KajiCEFCancelMessagePump();
void KajiCEFResetMessagePump();
