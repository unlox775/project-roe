# TODO: Minimum to Make Pidge Usable

This document lists the minimum changes needed to make Pidge run again **without adding new features**. The primary blocker is the deprecated bookmarklet bridge to ChatGPT's web UI. Everything below is scoped to replacing that bridge with direct LLM API calls.

---

## 1. Primary Blocker: Replace the Bookmarklet with Direct LLM API

### Current State

- Pidge sends prompts to a WebSocket server (`wss://abandoned-scared-halibut.gigalixirapp.com`) that relays them to a Phoenix channel.
- A browser bookmarklet runs on the ChatGPT page, joins that channel, injects the prompt into the textarea, simulates a click to submit, then uses a custom keyboard shortcut (Ctrl-Shift-C / Cmd-Shift-C) to copy the last message and send it back through the WebSocket.
- The bookmarklet manipulates the DOM (`document.getElementById('prompt-textarea')`, `textarea.dispatchEvent`, etc.). ChatGPT has since added JavaScript detection that blocks or breaks this.
- Each AI step in a Pidge script corresponds to a **conversation** (e.g., `:bard`, `:whip`). The session ID is `session:{conv}-{session}` (e.g., `session:bard-mystory`).

### What Needs to Happen

Replace `Pidge.WebClient` (and the Phoenix/Gigalixir relay) with a new module that calls a chat completions API directly. The entry point is `Pidge.Harness.CommandLine.push_to_api_and_wait_for_response/3`, which today does:

1. Build `data = %{ "message" => message, "human_input_mode" => human_input_mode }`
2. Build `channel = "session:#{conv}-#{session}"`
3. Call `Pidge.WebClient.send_and_wait_for_response(data, channel)`
4. Expect `{:ok, %{"body" => response_text}}`

The replacement must support `human_input_mode` (required, optional, or none) so the human-in-the-loop behavior is preserved. When human input is required/optional, the current flow pauses and waits for the human; the new flow will still need to support that (e.g., via stdin or a simple UI) but the LLM part should be direct API calls.

---

## 2. Maintaining Full Conversation Context

### How Chat APIs Work

Chat completion APIs (OpenAI, Anthropic, etc.) expect a `messages` array. Each message has `role` (`system`, `user`, `assistant`) and `content`. The full conversation history must be sent on each request; the model has no built-in memory. Example:

```json
[
  {"role": "system", "content": "You are a story writer."},
  {"role": "user", "content": "Generate a plot for a space opera."},
  {"role": "assistant", "content": "..."},
  {"role": "user", "content": "Now add a critique from a harsh editor."}
]
```

To simulate a continuous conversation, you:

1. Keep a `messages` array per conversation.
2. On each request: append the new user message, call the API with the full array, append the assistant response, return the response body.
3. Optionally support streaming: consume the stream and build the full assistant message as it arrives, then append to history.

### Separate Memory Per Agent

In Pidge, each conversation ID (e.g., `:bard`, `:whip`) is a different agent with a different job. They must have **separate** message histories:

- `bard` might be the story writer; its history is only story-drafting turns.
- `whip` might be the critique; its history is only critique turns.

The `messages` array for `bard` and the `messages` array for `whip` must not be merged. When `ai_pipethru(:whip, "whip/02_plot_critique")` runs, it sends the current input (from the previous step) to `whip`; `whip`'s history should include only `whip`-related turns. The pipeline passes **output** from one step as **input** to the next; each agent maintains its own context.

### Where to Store History

- Key by **session** (and within that by **conversation_id**). The session is already the run identifier (`--session`); the same session should tie to the same LLM conversation store so re-runs or rejoin commands see the same history.
- Minimal option: a **JSON file** per session, e.g. `release/{session}_llm.json`, with structure `%{ "bard" => [%{role, content}, ...], "whip" => [...] }`. Read on first use for a conversation, append user/assistant, write back. No GenServer required.
- Alternative: in-memory GenServer keyed by `{session, conv}` if you prefer to avoid file I/O; then history is lost when the process exits (resume only within the same run).

---

## 3. Framework / Library Options

| Option | Pros | Cons |
|--------|------|------|
| **OpenAI HTTP API directly** (via `Req` or `HTTPoison`) | Simple, full control, no new deps beyond HTTP. Works with any OpenAI-compatible API. | You handle message formatting and streaming yourself. |
| **Anthropic / other providers** | Same pattern; swap base URL and request shape. | Slightly different request/response formats. |
| **LangChain (Python)** | Mature, handles memory abstractions. | Pidge is Elixir; you'd need a separate Python service and IPC. Overkill for "replace the bookmarklet." |
| **LangChain.js** | Could run in Node, call from Elixir. | Adds Node dep, another process. |
| **Elixir LLM libs** (e.g., `openai_ex`, `ex_openai`) | Native Elixir. | Quality varies; some may be outdated. Verify they support chat completions and streaming. |

**Recommendation:** Use `Req` (or `HTTPoison`) to call the OpenAI Chat Completions API directly. It's straightforward, and you can later abstract over providers. No need for LangChain for this scope.

---

## 4. Concrete Steps to Implement (Go-Ahead-and-Make-It-So Checklist)

Use this as a step-by-step plan. Each step can be done in order; later passes can refine.

### Step 1: Add OpenAI Chat Completions Call

- Add `Req` (or similar) as a dependency.
- Create `Pidge.LLMClient` (or `Pidge.OpenAIClient`) with:
  - `send_message(conversation_id, message, opts \\ [])`
  - Reads API key from `System.get_env("OPENAI_API_KEY")` or config.
  - Sends a single request to `https://api.openai.com/v1/chat/completions` with `model`, `messages`, etc.
  - Returns `{:ok, response_body}` or `{:error, reason}`.
- For now, each call is stateless: `messages = [%{role: "user", content: message}]`. No history yet.

### Step 2: Per-Conversation Message History

- Add a GenServer (e.g., `Pidge.LLMConversationStore` or extend `SessionState`) to hold `%{ {session_id, conversation_id} => [messages] }`.
- When an AI step runs:
  - Look up or create the messages list for `{session, conv}`.
  - Append `%{role: "user", content: compiled_prompt}`.
  - Call the API with the full `messages` array.
  - Append `%{role: "assistant", "content": assistant_content}` to the list.
  - Return the assistant content as the step output.
- Ensure each conversation ID has its own key. `bard` and `whip` never share history.

### Step 3: Human-in-the-Loop (CLI Only)

- There is no UI; the command line is the human-in-the-loop interface.
- When the run needs human input (required or optional), it should **finish**, **output** the context the human needs to see, and **print the exact command to rejoin** with their answer (e.g. `pidge run --session xxx --from_step bird/01_example --human_input 'your input'` or `--input '...'` for the next step).
- The human runs that command with their response; execution resumes from the saved state. No stdin blocking—output and exit, then rejoin.
- Template interpolation (e.g. `{{ human_input }}`) is already done by the runtime before the message is sent; no extra work in the LLM layer.

### Step 4: Wire Into the Harness

- In `Pidge.Harness.CommandLine.push_to_api_and_wait_for_response/3`:
  - Replace the `Pidge.WebClient.send_and_wait_for_response` call with `Pidge.LLMClient.send_and_wait_for_response` (or equivalent), passing session and conversation id so the client can use the conversation store.
- When the run returns `{:required_input_callback, step}`: output the context the human needs, print the rejoin command (e.g. `pidge run --session S --from_step STEP --human_input '...'`), then halt. Do not block on stdin.
- Remove or deprecate the WebSocket client and the Gigalixir dependency. The bookmarklet can remain in the repo as legacy code but should not be part of the run path.

### Step 5: Configuration

- Support `OPENAI_API_KEY` via env.
- Optional: config for model name (e.g., `gpt-4` vs `gpt-4-turbo`), base URL (for compatible APIs), etc.
- Document in README how to set the key and run without the bookmarklet.

### Step 6: Streaming (Optional)

- The Chat Completions API supports streaming. For long outputs, streaming improves perceived latency.
- Implementation: use `stream: true` and parse SSE (Server-Sent Events). Accumulate chunks into the final assistant message, then append to history.
- Non-streaming is fine for the minimum; streaming can be a follow-up.

---

## 5. Knowledge Gap: Keeping Context in a Streamable Conversation

If you want the interaction to *feel* like ChatGPT (streaming tokens as they arrive), the flow is:

1. Send `messages` (history + new user message) with `stream: true`.
2. Receive SSE events; each event has a delta (e.g., `{"choices":[{"delta":{"content":"Hello"}}]}`).
3. Accumulate deltas into the full assistant message.
4. When the stream ends, append the full message to history.
5. Return the full message to the Pidge runtime so it can pipe to the next step.

The "full context" is still the same: you maintain a `messages` array and append the complete assistant reply after the stream finishes. Streaming only changes how you receive the reply, not how you store it.

**Libraries:** `Req` supports streaming responses. Parse the SSE format (newline-delimited, `data: {...}`) and extract `choices[0].delta.content`.

---

## 6. Summary

| Item | Status | Notes |
|------|--------|-------|
| Replace bookmarklet with LLM API | TODO | Main blocker |
| Per-conversation message history | TODO | Required for correct behavior |
| Human-in-the-loop input handling | TODO | Output context + rejoin command, then exit (CLI only) |
| Configuration (API key, model) | TODO | Env vars, minimal config |
| Remove WebSocket / Gigalixir dep | TODO | After LLM client works |
| Streaming | Optional | Improves UX, not required for MVP |

When you're ready, say: **"Go ahead and make it so"** and this checklist can be executed in order. No new features—just restoring the ability to run a Pidge app against a real LLM.
