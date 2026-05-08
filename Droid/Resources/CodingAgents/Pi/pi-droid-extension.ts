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

  const start = () => send("pi_activity", "start", context())
  const stop = () => send("pi_activity", "stop", context())
  const notifyCompletion = (body: string) => send("pi", "Pi", body)
  const notifyPermission = (body: string) => send("pi_permission_notice", "Pi", body)

  const sendSession = (ctx: any, source: string) => {
    const manager = ctx?.sessionManager
    const sessionID = manager?.getSessionId?.()
    if (!sessionID) return
    const body = JSON.stringify({
      sessionID: sanitize(sessionID),
      transcriptPath: sanitize(manager?.getSessionFile?.()),
      cwd: sanitize(manager?.getCwd?.() || process.env.DROID_WORKTREE_PATH),
      source: sanitize(source),
      projectID: process.env.DROID_PROJECT_ID,
      worktreeID: process.env.DROID_WORKTREE_ID,
      worktreePath: process.env.DROID_WORKTREE_PATH || "",
    })
    send("pi_session", "session", body)
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

  pi.on("session_start", async (event: any, ctx: any) => {
    sendSession(ctx, event?.reason || "session_start")
  })

  pi.on("before_agent_start", async (event: any, ctx: any) => {
    sendSession(ctx, "before_agent_start")
    start()
  })

  pi.on("tool_call", async (event: any, ctx: any) => {
    if (!shouldPrompt(event)) return
    const detail = summarize(event)
    send("pi_attention", "permission", detail)
    notifyPermission(`Needs permission: ${detail}`)
    const confirm = ctx?.ui?.confirm
    if (typeof confirm !== "function") return
    const approved = await confirm("Pi needs permission", `Allow ${detail}?`)
    if (approved === false) return { block: true, reason: "Denied by user" }
  })

  pi.on("agent_end", async (event: any) => {
    stop()
    const summary = latestAssistantText(event)
    if (summary) notifyCompletion(summary)
  })

  pi.on("session_shutdown", async () => {
    stop()
  })
}

function latestAssistantText(event: any) {
  const messages = Array.isArray(event?.messages) ? event.messages : []
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index]
    if (message?.role !== "assistant") continue
    const content = Array.isArray(message.content) ? message.content : []
    const text = content
      .filter((part: any) => part?.type === "text")
      .map((part: any) => sanitize(part?.text))
      .join(" ")
      .trim()
    if (text) return text.slice(0, 200)
  }
  return ""
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
