export const DroidNotificationPlugin = async ({ client }) => {
  let activityState = ""
  let completedAt = 0

  return {
    event: async ({ event }) => {
      const hookClientPath = process.env.DROID_HOOK_CLIENT_PATH
      const paneID = process.env.DROID_PANE_ID
      const projectID = process.env.DROID_PROJECT_ID
      const worktreeID = process.env.DROID_WORKTREE_ID
      const worktreePath = process.env.DROID_WORKTREE_PATH
      if (!hookClientPath || !paneID) return
      const context = projectID && worktreeID ? `${projectID},${worktreeID},${worktreePath || ""}` : ""

      const send = async (type, title, body) => {
        try {
          const { execFileSync } = await import("node:child_process")
          execFileSync(
            hookClientPath,
            ["send", type, paneID, title, body || ""],
            { stdio: "ignore", timeout: 3000 },
          )
        } catch {}
      }

      const sanitize = (value) => String(value || "").replace(/[\n\r|]+/g, " ").trim().slice(0, 500)

      const sendTranscript = async (kind, text) => {
        const cleaned = sanitize(text)
        if (!cleaned) return
        await send("opencode_transcript", kind, cleaned)
      }

      const sendSession = async () => {
        const sessionID = findSessionID(event)
        if (!sessionID) return
        const body = JSON.stringify({
          sessionID: sanitize(sessionID),
          source: sanitize(event.type),
          title: sanitize(event.properties?.title || event.properties?.name),
          projectID,
          worktreeID,
          worktreePath,
        })
        await send("opencode_session", "session", body)
      }

      const attentionDetail = () => {
        const properties = event.properties || {}
        return sanitize(
          properties.question ||
            properties.message ||
            properties.permission ||
            properties.tool ||
            properties.command ||
            properties.description ||
            event.type,
        )
      }

      const sendAttention = async (kind) => {
        await send("opencode_attention", kind, attentionDetail() || kind)
      }

      const sessionStatus = () => {
        const raw = event.properties?.status
        if (typeof raw === "string") return raw
        if (raw && typeof raw.type === "string") return raw.type
        if (raw && typeof raw.status === "string") return raw.status
        if (raw && typeof raw.state === "string") return raw.state
        if (typeof event.properties?.state === "string") return event.properties.state
        return ""
      }

      await sendSession()

      const start = async () => {
        completedAt = 0
        if (activityState === "start") return
        activityState = "start"
        await send("opencode_activity", "start", context)
      }

      const stop = async () => {
        if (activityState === "stop") return
        activityState = "stop"
        completedAt = Date.now()
        await send("opencode_activity", "stop", context)
      }

      if (event.type === "tui.command.execute") {
        await start()
        await sendTranscript("user", event.properties?.text || event.properties?.command)
        return
      }

      if (event.type === "tool.execute.before") {
        await start()
        await sendTranscript("tool", event.properties?.tool || event.properties?.name)
        return
      }

      if (event.type === "session.status") {
        const status = sessionStatus()
        if (
          status === "active" ||
          status === "busy" ||
          status === "running" ||
          status === "loading" ||
          status === "retry"
        ) {
          await start()
          return
        }
        if (status === "idle" || status === "error") {
          await stop()
          return
        }
      }

      if (event.type === "message.updated" || event.type === "message.part.updated") {
        if (completedAt && Date.now() - completedAt < 1000) return
        await start()
        return
      }

      if (event.type === "permission.asked") {
        await sendAttention("permission")
        return
      }

      if (event.type === "question.asked") {
        await sendAttention("question")
        return
      }

      if (event.type === "session.error") {
        await sendAttention("error")
        return
      }

      if (event.type !== "session.idle") return

      await stop()

      const sessionID = event.properties.sessionID
      let body = "Session completed"

      try {
        const result = await client.session.messages({
          path: { id: sessionID },
          query: { limit: 3 },
        })
        const messages = result.data || []
        const lastAssistant = [...messages]
          .reverse()
          .find((m) => m.info.role === "assistant")
        if (lastAssistant) {
          const textParts = (lastAssistant.parts || []).filter(
            (p) => p.type === "text",
          )
          const text = textParts.map((p) => p.text || "").join("")
          if (text) {
            body = sanitize(text).slice(0, 200)
            await sendTranscript("assistant", text)
          }
        }
      } catch {}

    },
  }
}

function findSessionID(value) {
  const direct = value?.properties?.sessionID || value?.properties?.sessionId || value?.sessionID || value?.sessionId
  if (direct) return direct
  if (String(value?.type || "").startsWith("session.")) {
    const id = value?.properties?.id || value?.id
    if (id) return id
  }
  return findNestedSessionID(value, 0)
}

function findNestedSessionID(value, depth) {
  if (!value || depth > 4 || typeof value !== "object") return ""
  for (const [key, child] of Object.entries(value)) {
    const lower = key.toLowerCase()
    if (["sessionid", "session_id"].includes(lower) && child) return child
    if (lower === "session" && child && typeof child === "object") {
      const id = child.id || child.sessionID || child.sessionId
      if (id) return id
    }
  }
  for (const child of Object.values(value)) {
    const nested = findNestedSessionID(child, depth + 1)
    if (nested) return nested
  }
  return ""
}
