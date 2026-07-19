import { describe, expect, test } from "bun:test";
import {
	APP_POWER_ASSERTION_OWNERSHIP_ENV,
	shouldAcquireRuntimePowerAssertion,
} from "../src/session/power-assertion-ownership";

describe("runtime power assertion ownership", () => {
	test("standalone runtime keeps native assertion ownership", () => {
		expect(shouldAcquireRuntimePowerAssertion({})).toBe(true);
	});

	test("Kaji-owned runtime skips duplicate assertion", () => {
		expect(shouldAcquireRuntimePowerAssertion({ [APP_POWER_ASSERTION_OWNERSHIP_ENV]: "1" })).toBe(false);
	});

	test("only the explicit ownership value suppresses runtime assertions", () => {
		expect(shouldAcquireRuntimePowerAssertion({ [APP_POWER_ASSERTION_OWNERSHIP_ENV]: "0" })).toBe(true);
		expect(shouldAcquireRuntimePowerAssertion({ [APP_POWER_ASSERTION_OWNERSHIP_ENV]: "true" })).toBe(true);
	});
});
