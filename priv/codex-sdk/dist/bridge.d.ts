/**
 * HAL Codex SDK Bridge
 *
 * This bridge connects Elixir (via Port stdin/stdout) to the OpenAI Codex SDK.
 * It receives JSON commands on stdin and returns JSON responses on stdout.
 *
 * Commands:
 * - start_thread: Create a new Codex thread
 * - run: Execute a prompt on a thread
 * - resume_thread: Resume an existing thread by ID
 * - ping: Health check
 * - shutdown: Clean exit
 *
 * Communication Protocol:
 * - Each line is a complete JSON object
 * - Request: { id: string, command: string, ...params }
 * - Response: { id: string, success: boolean, result?: any, error?: string }
 */
export {};
//# sourceMappingURL=bridge.d.ts.map