import * as fs from "node:fs";
import { parseSessionEntries } from "./session-manager";

export function readSubagentTranscript(filePath: string, fromByte = 0) {
	try {
		const stat = fs.statSync(filePath);
		if (stat.size <= fromByte) return { entries: [], fromByte, toByte: stat.size };
		const fd = fs.openSync(filePath, "r");
		const buffer = Buffer.alloc(stat.size - fromByte);
		try {
			fs.readSync(fd, buffer, 0, buffer.length, fromByte);
		} finally {
			fs.closeSync(fd);
		}
		return {
			entries: parseSessionEntries(buffer.toString("utf8")),
			fromByte,
			toByte: stat.size,
		};
	} catch (error) {
		return {
			entries: [],
			fromByte,
			toByte: fromByte,
			error: error instanceof Error ? error.message : String(error),
		};
	}
}
