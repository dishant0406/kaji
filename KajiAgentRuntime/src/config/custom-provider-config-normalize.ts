const PROVIDER_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export function normalizeRequired(value: string | undefined, label: string): string {
	const result = normalizeOptional(value);
	if (!result) throw new Error(`${label} is required.`);
	return result;
}

export function normalizeOptional(value: string | undefined): string | undefined {
	const result = value?.trim();
	return result ? result : undefined;
}

export function validateProviderId(id: string): void {
	if (!PROVIDER_ID_PATTERN.test(id)) throw new Error("Provider ID can use letters, numbers, dots, hyphens, and underscores.");
}

export function normalizeHeaders(headers: Record<string, string> | undefined): Record<string, string> | undefined {
	if (!headers) return undefined;
	const next: Record<string, string> = {};
	for (const [key, value] of Object.entries(headers)) {
		const name = key.trim();
		const headerValue = value.trim();
		if (name && headerValue) next[name] = headerValue;
	}
	return Object.keys(next).length > 0 ? next : undefined;
}

export function uniqueInput(input: Array<"text" | "image">): Array<"text" | "image"> {
	return Array.from(new Set(input));
}

export function cleanValue(value: unknown): unknown {
	if (Array.isArray(value)) return value.map(cleanValue).filter(item => item !== undefined);
	if (!value || typeof value !== "object") return value;
	const result: Record<string, unknown> = {};
	for (const [key, item] of Object.entries(value)) {
		const cleaned = cleanValue(item);
		if (cleaned === undefined) continue;
		if (Array.isArray(cleaned) && cleaned.length === 0) continue;
		if (cleaned && typeof cleaned === "object" && !Array.isArray(cleaned) && Object.keys(cleaned).length === 0) continue;
		result[key] = cleaned;
	}
	return result;
}
