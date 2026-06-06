import { describe, expect, test } from "bun:test";
import { getDefault, Settings } from "../config/settings";
import {
	applyRuntimeProfileDefaultSettings,
	getRuntimeProfile,
	KAJI_RPC_DEFAULT_SETTING_PATHS,
	kajiRpcRuntimeProfile,
	runtimeProfiles,
} from "./profile";

describe("kaji runtime profile", () => {
	test("mirrors the existing rpc default setting list", () => {
		expect(kajiRpcRuntimeProfile().defaultSettingPaths).toEqual(KAJI_RPC_DEFAULT_SETTING_PATHS);
	});

	test("applies schema defaults over existing overrides", () => {
		const settings = Settings.isolated({
			"todo.enabled": !getDefault("todo.enabled"),
			"async.maxJobs": Number(getDefault("async.maxJobs")) + 10,
			"memory.backend": "hindsight",
		});

		applyRuntimeProfileDefaultSettings(settings, kajiRpcRuntimeProfile());

		for (const settingPath of KAJI_RPC_DEFAULT_SETTING_PATHS) {
			expect(settings.get(settingPath)).toEqual(getDefault(settingPath));
		}
	});

	test("captures the production rpc harness shape", () => {
		const profile = kajiRpcRuntimeProfile();

		expect(profile.id).toBe("kaji-rpc-build");
		expect(profile.mode).toBe("rpc");
		expect(profile.permissionMode).toBe("read-allow");
		expect(profile.toolPatterns).toContain("read");
		expect(profile.toolPatterns).toContain("bash");
		expect(profile.toolPatterns).toContain("edit");
		expect(profile.toolPatterns).toContain("todo_read");
		expect(profile.hiddenToolPatterns).toContain("yield");
		expect(profile.subagents.maxRecursionDepth).toBe(getDefault("task.maxRecursionDepth"));
	});

	test("defines production profile variants", () => {
		expect(runtimeProfiles().map(profile => profile.id)).toEqual([
			"kaji-rpc-build",
			"kaji-rpc-plan",
			"kaji-rpc-explore",
			"kaji-rpc-review",
			"kaji-subagent-default",
			"kaji-subagent-explore-lite",
		]);
		expect(getRuntimeProfile("kaji-subagent-explore-lite").toolPatterns).toContain("kaji_code_graph_*");
		expect(getRuntimeProfile("kaji-rpc-plan").toolPatterns).not.toContain("edit");
	});
});
