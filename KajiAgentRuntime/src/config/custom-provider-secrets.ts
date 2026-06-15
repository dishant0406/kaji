export type CustomProviderApiKeySource = "none" | "environment" | "literal";

export interface CustomProviderApiKeyStatus {
	configured: boolean;
	source: CustomProviderApiKeySource;
	name?: string;
	resolved: boolean;
}

export function resolveProviderApiKey(keyConfig: string | undefined): string | undefined {
	if (!keyConfig) return undefined;
	const envValue = Bun.env[keyConfig];
	if (envValue) return envValue;
	if (looksLikeEnvironmentVariable(keyConfig)) return undefined;
	return keyConfig;
}

export function providerApiKeyStatus(keyConfig: string | undefined): CustomProviderApiKeyStatus {
	if (!keyConfig) return { configured: false, source: "none", resolved: false };
	if (looksLikeEnvironmentVariable(keyConfig)) {
		return {
			configured: true,
			source: "environment",
			name: keyConfig,
			resolved: Boolean(Bun.env[keyConfig]),
		};
	}
	return { configured: true, source: "literal", resolved: true };
}

export function looksLikeEnvironmentVariable(value: string): boolean {
	return /^[A-Z_][A-Z0-9_]*$/.test(value.trim());
}
