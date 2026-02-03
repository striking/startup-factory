/**
 * HAL Agent SDK Bridge
 *
 * This bridge connects Elixir (via Port stdin/stdout) to the Claude Agent SDK.
 * It receives JSON commands on stdin and returns JSON responses on stdout.
 *
 * Commands:
 * - query: Send a prompt to Claude Agent SDK
 * - create_session: Create a new session (implicit via query)
 * - close_session: Clean up a session
 * - ping: Health check
 *
 * Communication Protocol:
 * - Each line is a complete JSON object
 * - Request: { id: string, command: string, ...params }
 * - Response: { id: string, success: boolean, result?: any, error?: string }
 */
export {};
//# sourceMappingURL=bridge.d.ts.map