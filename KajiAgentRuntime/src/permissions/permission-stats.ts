import type { PermissionCategory, PermissionKey } from "./permission-types";

export class PermissionStats {
	#requestsByKey = new Map<string, number>();
	#deniesByKey = new Map<string, number>();
	#requestsByCategory = new Map<PermissionCategory, number>();
	#deniesByCategory = new Map<PermissionCategory, number>();
	#requestCount = 0;
	#denyCount = 0;

	get requestCount(): number {
		return this.#requestCount;
	}

	get denyCount(): number {
		return this.#denyCount;
	}

	recordRequest(key: PermissionKey): void {
		this.#requestCount++;
		increment(this.#requestsByKey, key);
		increment(this.#requestsByCategory, permissionCategoryForKey(key));
	}

	recordDeny(key: PermissionKey): void {
		this.#denyCount++;
		increment(this.#deniesByKey, key);
		increment(this.#deniesByCategory, permissionCategoryForKey(key));
	}

	snapshot() {
		return {
			requestCount: this.#requestCount,
			denyCount: this.#denyCount,
			requestCountByKey: Object.fromEntries(this.#requestsByKey),
			denyCountByKey: Object.fromEntries(this.#deniesByKey),
			requestCountByCategory: Object.fromEntries(this.#requestsByCategory),
			denyCountByCategory: Object.fromEntries(this.#deniesByCategory),
		};
	}
}

export function permissionCategoryForKey(key: PermissionKey): PermissionCategory {
	if (key === "browser") return "browser";
	if (key.startsWith("kaji:")) return "host";
	if (key.startsWith("mcp:")) return "mcp";
	if (key === "web") return "web";
	return "runtime";
}

function increment<TKey>(map: Map<TKey, number>, key: TKey): void {
	map.set(key, (map.get(key) ?? 0) + 1);
}
