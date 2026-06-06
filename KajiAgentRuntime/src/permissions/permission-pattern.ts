export function matchPermissionPattern(pattern: string, value: string): boolean {
	if (pattern === "*" || pattern === value) return true;
	const escaped = pattern.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
	return new RegExp(`^${escaped}$`).test(value);
}

export function matchesAnyPermissionPattern(patterns: readonly string[], value: string): boolean {
	return patterns.some(pattern => matchPermissionPattern(pattern, value));
}
