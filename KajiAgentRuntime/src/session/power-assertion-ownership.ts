export const APP_POWER_ASSERTION_OWNERSHIP_ENV = "KAJI_APP_OWNS_POWER_ASSERTIONS";

export function shouldAcquireRuntimePowerAssertion(environment: NodeJS.ProcessEnv = process.env): boolean {
	return environment[APP_POWER_ASSERTION_OWNERSHIP_ENV] !== "1";
}
