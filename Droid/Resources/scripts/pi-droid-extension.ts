import type { ExtensionAPI } from "@mariozechner/pi-coding-agent"
import { execFileSync } from "node:child_process"

export default function (pi: ExtensionAPI) {
  const hookClientPath = process.env.DROID_HOOK_CLIENT_PATH
  const paneID = process.env.DROID_PANE_ID

  const send = (type: string, title: string, body: string) => {
    if (!hookClientPath || !paneID) return
    try {
      execFileSync(hookClientPath, ["send", type, paneID, title, sanitize(body)], {
        stdio: "ignore",
        timeout: 3000,
      })
    } catch {}
  }

  const summarize = (event: any) => {
    const tool = sanitize(event?.toolName || event?.name || "tool")
    const input = event?.input || event?.args || {}
    const command = input.command || input.cmd || input.path || input.file || input.filePath
    if (command) return `${tool}: ${sanitize(command)}`
    return `${tool}: ${sanitize(JSON.stringify(input)).slice(0, 300)}`
  }

  const shouldPrompt = (event: any) => {
    if (process.env.DROID_PI_PERMISSION_MODE !== "prompt") return false
    const tool = String(event?.toolName || event?.name || "").toLowerCase()
    return ["bash", "write", "edit", "multi_edit", "apply_patch", "mcp"].some((name) => tool.includes(name))
  }

  pi.on("before_agent_start", async () => {
    send("pi_activity", "start", context())
  })

  pi.on("tool_call", async (event: any, ctx: any) => {
    if (!shouldPrompt(event)) return
    const detail = summarize(event)
    send("pi_attention", "permission", detail)
    const confirm = ctx?.ui?.confirm
    if (typeof confirm !== "function") return
    const approved = await confirm(`Allow ${detail}?`)
    if (approved === false) return { block: true, reason: "Denied by user" }
  })
}

function context() {
  const projectID = process.env.DROID_PROJECT_ID
  const worktreeID = process.env.DROID_WORKTREE_ID
  const worktreePath = process.env.DROID_WORKTREE_PATH || ""
  return projectID && worktreeID ? `${projectID},${worktreeID},${worktreePath}` : ""
}

function sanitize(value: unknown) {
  return String(value || "")
    .replace(/[\n\r|]+/g, " ")
    .trim()
    .slice(0, 500)
}
