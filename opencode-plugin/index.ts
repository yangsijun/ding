import type { Plugin } from "@opencode-ai/plugin"
import { spawn } from "child_process"

const plugin: Plugin = async (input) => {
  let lastPrompt: string | null = null
  let mainSessionID: string | null = null
  let lastUserMessageID: string | null = null

  function truncate(text: string, maxLength: number): string {
    const cleaned = text.replace(/\n/g, " ").trim()
    if (cleaned.length <= maxLength) return cleaned
    return cleaned.substring(0, maxLength) + "…"
  }

  function shortenHome(dir: string): string {
    const home = process.env.HOME || process.env.USERPROFILE || ""
    if (home && dir.startsWith(home)) return "~" + dir.slice(home.length)
    return dir
  }

  function sendNotification(body: string, status: string) {
    const proc = spawn("ding", ["notify", body, "--title", "ding · OpenCode", "--status", status], {
      stdio: "ignore",
      detached: true,
    })
    proc.unref()
  }

  return {
    event: async ({ event }) => {
      // Track user prompts via message events (not chat.message hook)
      if (event.type === "message.updated") {
        const msg = (event.properties as any).info
        if (msg?.role === "user") {
          mainSessionID = msg.sessionID
          lastUserMessageID = msg.id
        }
      }

      // Capture user's typed text from part updates
      if (event.type === "message.part.updated") {
        const part = (event.properties as any).part
        if (
          part?.type === "text" &&
          !part.synthetic &&
          part.messageID === lastUserMessageID
        ) {
          const text = (part.text || "").replace(/\n/g, " ").trim()
          if (text) {
            lastPrompt = text
          }
        }
      }

      if (event.type === "session.idle") {
        const sessionID = event.properties.sessionID
        if (mainSessionID && sessionID !== mainSessionID) return

        const cwd = shortenHome(input.project?.path || input.directory || process.cwd())
        const summary = lastPrompt ? `Done: ${truncate(lastPrompt, 80)}` : "Task completed"
        const body = `${cwd}\n${summary}`

        sendNotification(body, "success")

        lastPrompt = null
      }

      if (event.type === "session.error") {
        const sessionID = (event.properties as any).sessionID
        if (mainSessionID && sessionID !== mainSessionID) return

        const cwd = shortenHome(input.project?.path || input.directory || process.cwd())
        const error = event.properties.error
        const msg =
          error && "data" in error && typeof (error as any).data?.message === "string"
            ? (error as any).data.message
            : "Unknown error"
        const body = `${cwd}\nFailed: ${truncate(msg, 80)}`

        sendNotification(body, "failure")
      }

      if (event.type === "question.asked") {
        const props = event.properties as { sessionID?: string; questions?: Array<{ question?: string; header?: string }> }
        const sessionID = props.sessionID
        if (mainSessionID && sessionID !== mainSessionID) return

        const cwd = shortenHome(input.project?.path || input.directory || process.cwd())
        const question = props.questions?.[0]?.header || props.questions?.[0]?.question || "Needs your input"
        const body = `${cwd}\nAsked: ${truncate(question, 80)}`

        sendNotification(body, "warning")
      }
    },
  }
}

export default plugin
