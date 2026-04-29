export const DroidNotificationPlugin = async ({ client }) => ({
  event: async ({ event }) => {
    const socketPath = process.env.DROID_SOCKET_PATH
    const paneID = process.env.DROID_PANE_ID
    const projectID = process.env.DROID_PROJECT_ID
    const worktreeID = process.env.DROID_WORKTREE_ID
    if (!socketPath || !paneID) return
    const context = projectID && worktreeID ? `${projectID},${worktreeID}` : ""

    const send = async (payload) => {
      try {
        const { createConnection } = await import("net")
        const conn = createConnection({ path: socketPath })
        conn.on("error", () => {})
        conn.write(payload, () => conn.end())
        await new Promise((resolve) => {
          conn.on("close", resolve)
          setTimeout(resolve, 3000)
        })
      } catch {}
    }

    const sessionStatus = () => {
      const raw = event.properties?.status
      if (typeof raw === "string") return raw
      if (raw && typeof raw.type === "string") return raw.type
      return ""
    }

    const start = async () => {
      await send(`opencode_activity|${paneID}|start|${context}`)
    }

    const stop = async () => {
      await send(`opencode_activity|${paneID}|stop|${context}`)
    }

    if (event.type === "tui.command.execute") {
      await start()
      return
    }

    if (event.type === "tool.execute.before") {
      await start()
      return
    }

    if (event.type === "session.status") {
      const status = sessionStatus()
      if (status === "active" || status === "busy" || status === "retry") {
        await start()
        return
      }
      if (status === "idle" || status === "error") {
        await stop()
        return
      }
    }

    if (
      event.type === "question.asked" ||
      event.type === "permission.asked" ||
      event.type === "session.error"
    ) {
      await stop()
      return
    }

    if (event.type !== "session.idle") return

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
          body = text.replace(/[\n\r|]+/g, " ").slice(0, 200)
        }
      }
    } catch {}

    const payload = `opencode|${paneID}|OpenCode|${body}`
    await stop()
    await send(payload)
  },
})
