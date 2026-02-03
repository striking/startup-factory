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

import { createInterface } from 'readline';
import { createSdkMcpServer, query as sdkQuery, tool, type SDKMessage } from '@anthropic-ai/claude-agent-sdk';
import { z } from 'zod';

// Type definitions
interface Command {
  id: string;
  command: 'query' | 'create_session' | 'close_session' | 'ping' | 'shutdown' | 'hal_tool_result';
  prompt?: string;
  session_id?: string;
  options?: QueryOptions;
  context?: Record<string, unknown>;
  success?: boolean;
  result?: unknown;
  error?: unknown;
}

interface QueryOptions {
  model?: string;
  system_prompt?: string;
  allowed_tools?: string[];
  timeout?: number;
  resume?: string;
}

interface Response {
  id: string;
  success: boolean;
  result?: string;
  session_id?: string;
  error?: string;
  messages?: SDKMessage[];
}

type CallToolResult = {
  content: Array<{ type: 'text'; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
};

// Active sessions cache (for session management)
const activeSessions = new Map<string, { lastUsed: number }>();
const pendingToolCalls = new Map<
  string,
  { resolve: (value: Command) => void; reject: (error: Error) => void; timer: NodeJS.Timeout }
>();
let toolCallCounter = 0;

const HAL_AUTO_ALLOWED_TOOLS = [
  // HAL MCP server tools are gated by HAL's own approvals, so they should not be
  // blocked by Claude Code's permission prompts.
  'mcp__hal__hal_memory_search',
  'mcp__hal__hal_memory_store',
  'mcp__hal__hal_memory_forget',
  'mcp__hal__hal_calendar_get_events',
  'mcp__hal__hal_calendar_create_event',
  'mcp__hal__hal_email_get_unread',
  'mcp__hal__hal_email_send',
  'mcp__hal__hal_tasks_list',
  'mcp__hal__hal_tasks_create',
  'mcp__hal__hal_tasks_complete',
  'mcp__hal__hal_send_notification',
  'mcp__hal__hal_delegate_to_codex',
  'mcp__hal__hal_delegate_to_jules',
  'mcp__hal__hal_delegate_to_gemini',
  'mcp__hal__hal_check_delegation_status',
  'mcp__hal__hal_codops_create_change_request',
  'mcp__hal__hal_codops_apply_change_request',
  'mcp__hal__hal_mcp_start_named_connection',
  'mcp__hal__hal_mcp_list_connections',
  'mcp__hal__hal_mcp_list_tools',
  'mcp__hal__hal_mcp_call_tool',
  'mcp__hal__hal_browser_navigate',
  'mcp__hal__hal_browser_snapshot',
  'mcp__hal__hal_browser_click',
  'mcp__hal__hal_browser_fill',
  'mcp__hal__hal_browser_screenshot',
  'mcp__hal__hal_browser_evaluate',
  'mcp__hal__hal_browser_console',
  'mcp__hal__hal_browser_network',
  'mcp__hal__hal_self_update_personality',
  'mcp__hal__hal_self_update_preference',
  'mcp__hal__hal_self_set_goal',
  'mcp__hal__hal_self_update_goal',
  'mcp__hal__hal_self_reflect',
  'mcp__hal__hal_get_self_status',
  'mcp__hal__hal_skill_run',
  // Also include un-prefixed names in case the SDK changes naming behavior.
  'hal_memory_search',
  'hal_memory_store',
  'hal_memory_forget',
  'hal_calendar_get_events',
  'hal_calendar_create_event',
  'hal_email_get_unread',
  'hal_email_send',
  'hal_tasks_list',
  'hal_tasks_create',
  'hal_tasks_complete',
  'hal_send_notification',
  'hal_delegate_to_codex',
  'hal_delegate_to_jules',
  'hal_delegate_to_gemini',
  'hal_check_delegation_status',
  'hal_codops_create_change_request',
  'hal_codops_apply_change_request',
  'hal_mcp_start_named_connection',
  'hal_mcp_list_connections',
  'hal_mcp_list_tools',
  'hal_mcp_call_tool',
  'hal_browser_navigate',
  'hal_browser_snapshot',
  'hal_browser_click',
  'hal_browser_fill',
  'hal_browser_screenshot',
  'hal_browser_evaluate',
  'hal_browser_console',
  'hal_browser_network',
  'hal_self_update_personality',
  'hal_self_update_preference',
  'hal_self_set_goal',
  'hal_self_update_goal',
  'hal_self_reflect',
  'hal_get_self_status',
  'hal_skill_run'
];

function mergeAllowedTools(tools: string[] | undefined): string[] {
  const merged = new Set<string>();
  for (const toolName of tools ?? []) merged.add(toolName);
  for (const toolName of HAL_AUTO_ALLOWED_TOOLS) merged.add(toolName);
  return Array.from(merged);
}

// Session cleanup interval (30 minutes)
const SESSION_TIMEOUT = 30 * 60 * 1000;

// Send a response back to Elixir
function sendResponse(response: Response): void {
  console.log(JSON.stringify(response));
}

// Send an error response
function sendError(id: string, error: string): void {
  sendResponse({ id, success: false, error });
}

function sendEvent(payload: unknown): void {
  console.log(JSON.stringify(payload));
}

// Extract text content from assistant messages
function extractTextFromMessage(msg: SDKMessage): string | null {
  if (msg.type !== 'assistant') return null;

  const textContent = msg.message.content
    .filter((block: { type: string }) => block.type === 'text')
    .map((block: { type: string; text?: string }) => block.text || '')
    .join('');

  return textContent || null;
}

function safeJson(value: unknown): string {
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

async function callHalTool(
  toolName: string,
  args: Record<string, unknown>,
  context: Record<string, unknown>
): Promise<CallToolResult> {
  const toolCallId = `tool-${Date.now()}-${++toolCallCounter}`;

  sendEvent({
    type: 'hal_tool_call',
    id: toolCallId,
    tool_name: toolName,
    args,
    context
  });

  const cmd = await new Promise<Command>((resolve, reject) => {
    const timer = setTimeout(() => {
      pendingToolCalls.delete(toolCallId);
      reject(new Error(`Tool call timed out: ${toolName}`));
    }, 120_000);

    pendingToolCalls.set(toolCallId, { resolve, reject, timer });
  });

  if (cmd.success === true) {
    const result = cmd.result as unknown;
    const structured =
      typeof result === 'object' && result !== null ? (result as Record<string, unknown>) : { result };

    return {
      content: [{ type: 'text', text: safeJson(result) }],
      structuredContent: structured
    };
  }

  const error = cmd.error as unknown;
  const structured =
    typeof error === 'object' && error !== null ? (error as Record<string, unknown>) : { error };

  return {
    content: [{ type: 'text', text: safeJson(error) }],
    structuredContent: structured,
    isError: true
  };
}

function buildHalMcpServer(context: Record<string, unknown>) {
  const tools = [
    tool(
      'hal_memory_search',
      'Search HAL semantic memory (vector recall).',
      {
        query: z.string(),
        source: z.string().optional(),
        limit: z.number().int().positive().optional(),
        threshold: z.number().min(0).max(1).optional()
      },
      async (args) => callHalTool('hal_memory_search', args, context)
    ),
    tool(
      'hal_memory_store',
      'Store information in HAL semantic memory.',
      {
        content: z.string(),
        // Prefer `source`; `type` is legacy and mapped server-side.
        source: z.string().optional(),
        type: z.string().optional(),
        metadata: z.record(z.string(), z.any()).optional()
      },
      async (args) => callHalTool('hal_memory_store', args, context)
    ),
    tool(
      'hal_memory_forget',
      'Delete a memory from HAL semantic memory by id.',
      {
        memory_id: z.string()
      },
      async (args) => callHalTool('hal_memory_forget', args, context)
    ),
    tool(
      'hal_calendar_get_events',
      'List upcoming calendar events.',
      {
        start_date: z.string().optional(),
        end_date: z.string().optional(),
        limit: z.number().int().positive().optional()
      },
      async (args) => callHalTool('hal_calendar_get_events', args, context)
    ),
    tool(
      'hal_calendar_create_event',
      'Create a calendar event.',
      {
        title: z.string(),
        start_time: z.string(),
        end_time: z.string(),
        description: z.string().optional(),
        location: z.string().optional(),
        attendees: z.array(z.string()).optional()
      },
      async (args) => callHalTool('hal_calendar_create_event', args, context)
    ),
    tool(
      'hal_email_get_unread',
      'List unread emails (Gmail).',
      {
        limit: z.number().int().positive().optional(),
        from: z.string().optional(),
        subject_contains: z.string().optional()
      },
      async (args) => callHalTool('hal_email_get_unread', args, context)
    ),
    tool(
      'hal_email_send',
      'Send an email (Gmail).',
      {
        to: z.union([z.string(), z.array(z.string())]),
        subject: z.string(),
        body: z.string(),
        cc: z.union([z.string(), z.array(z.string())]).optional(),
        bcc: z.union([z.string(), z.array(z.string())]).optional()
      },
      async (args) => callHalTool('hal_email_send', args, context)
    ),
    tool(
      'hal_tasks_list',
      'List tasks (Linear).',
      {
        status: z.string().optional(),
        limit: z.number().int().positive().optional(),
        project: z.string().optional()
      },
      async (args) => callHalTool('hal_tasks_list', args, context)
    ),
    tool(
      'hal_tasks_create',
      'Create a task (Linear).',
      {
        title: z.string(),
        description: z.string().optional(),
        priority: z.enum(['low', 'medium', 'high', 'urgent']).optional(),
        team_id: z.string()
      },
      async (args) => callHalTool('hal_tasks_create', args, context)
    ),
    tool(
      'hal_tasks_complete',
      'Mark a task complete (Linear).',
      {
        task_id: z.string()
      },
      async (args) => callHalTool('hal_tasks_complete', args, context)
    ),
    tool(
      'hal_send_notification',
      'Send a notification to the user.',
      {
        message: z.string(),
        channel: z.enum(['auto', 'telegram', 'email']).optional(),
        priority: z.enum(['low', 'normal', 'high', 'urgent']).optional(),
        silent: z.boolean().optional()
      },
      async (args) => callHalTool('hal_send_notification', args, context)
    ),
    tool(
      'hal_delegate_to_codex',
      'Delegate a complex coding task to OpenAI Codex. If approval_token is omitted, HAL will create an approval request and return a token to approve in /approvals.',
      {
        task: z.string(),
        project_path: z.string().optional(),
        approval_token: z.string().optional()
      },
      async (args) => callHalTool('hal_delegate_to_codex', args, context)
    ),
    tool(
      'hal_delegate_to_jules',
      'Delegate a long-running background task to Jules. If approval_token is omitted, HAL will create an approval request and return a token to approve in /approvals.',
      {
        task: z.string(),
        repo: z.string().optional(),
        priority: z.enum(['low', 'normal', 'high']).optional(),
        approval_token: z.string().optional()
      },
      async (args) => callHalTool('hal_delegate_to_jules', args, context)
    ),
    tool(
      'hal_delegate_to_gemini',
      'Delegate a summarization or completion task to Gemini.',
      {
        text: z.string(),
        operation: z.enum(['summarize', 'complete', 'delegate']),
        max_length: z.number().int().positive().optional(),
        style: z.enum(['paragraph', 'bullets', 'key_points']).optional()
      },
      async (args) => callHalTool('hal_delegate_to_gemini', args, context)
    ),
    tool(
      'hal_check_delegation_status',
      'Check the status of a delegated task (Codex, Jules, or Gemini).',
      {
        task_id: z.string(),
        agent: z.enum(['codex', 'jules', 'gemini'])
      },
      async (args) => callHalTool('hal_check_delegation_status', args, context)
    ),
    tool(
      'hal_codops_create_change_request',
      'Create a codops ChangeRequest (isolated worktree → diff → tests). If approval_token is omitted, HAL will create an approval request and return a token to approve in /approvals.',
      {
        task: z.string(),
        title: z.string().optional(),
        test_command: z.string().optional(),
        approval_token: z.string().optional()
      },
      async (args) => callHalTool('hal_codops_create_change_request', args, context)
    ),
    tool(
      'hal_codops_apply_change_request',
      'Apply a ready ChangeRequest patch to the main repo. If approval_token is omitted, HAL will create an approval request and return a token to approve in /approvals.',
      {
        change_request_id: z.string(),
        force: z.boolean().optional(),
        approval_token: z.string().optional()
      },
      async (args) => callHalTool('hal_codops_apply_change_request', args, context)
    ),
    tool(
      'hal_mcp_start_named_connection',
      'Start a named MCP server connection from ~/.hal/mcp-servers.json. If approval_token is omitted, HAL will create an approval request and return a token to approve in /approvals.',
      {
        name: z.string(),
        approval_token: z.string().optional()
      },
      async (args) => callHalTool('hal_mcp_start_named_connection', args, context)
    ),
    tool(
      'hal_mcp_list_connections',
      'List active MCP connections.',
      {},
      async (args) => callHalTool('hal_mcp_list_connections', args, context)
    ),
    tool(
      'hal_mcp_list_tools',
      'List tools for a named MCP connection.',
      {
        name: z.string()
      },
      async (args) => callHalTool('hal_mcp_list_tools', args, context)
    ),
    tool(
      'hal_mcp_call_tool',
      'Call a tool on a named MCP connection. If approval_token is omitted, HAL will create an approval request and return a token to approve in /approvals.',
      {
        name: z.string(),
        tool: z.string(),
        arguments: z.record(z.string(), z.any()).optional(),
        approval_token: z.string().optional()
      },
      async (args) => callHalTool('hal_mcp_call_tool', args, context)
    ),
    tool(
      'hal_browser_navigate',
      'Navigate to a URL in the browser (devtools or extension).',
      {
        url: z.string(),
        mode: z.enum(['devtools', 'extension']).optional(),
        wait_for: z.string().optional()
      },
      async (args) => callHalTool('hal_browser_navigate', args, context)
    ),
    tool(
      'hal_browser_snapshot',
      'Take an accessibility tree snapshot of the current page (devtools).',
      {
        verbose: z.boolean().optional()
      },
      async (args) => callHalTool('hal_browser_snapshot', args, context)
    ),
    tool(
      'hal_browser_click',
      'Click an element (by uid or selector).',
      {
        uid: z.string().optional(),
        selector: z.string().optional(),
        double_click: z.boolean().optional()
      },
      async (args) => callHalTool('hal_browser_click', args, context)
    ),
    tool(
      'hal_browser_fill',
      'Fill a form field (by uid or selector).',
      {
        uid: z.string().optional(),
        selector: z.string().optional(),
        value: z.string()
      },
      async (args) => callHalTool('hal_browser_fill', args, context)
    ),
    tool(
      'hal_browser_screenshot',
      'Take a screenshot (devtools).',
      {
        full_page: z.boolean().optional(),
        selector: z.string().optional()
      },
      async (args) => callHalTool('hal_browser_screenshot', args, context)
    ),
    tool(
      'hal_browser_evaluate',
      'Evaluate JavaScript (devtools).',
      {
        script: z.string()
      },
      async (args) => callHalTool('hal_browser_evaluate', args, context)
    ),
    tool(
      'hal_browser_console',
      'List browser console messages (devtools).',
      {
        level: z.string().optional(),
        limit: z.number().int().positive().optional()
      },
      async (args) => callHalTool('hal_browser_console', args, context)
    ),
    tool(
      'hal_browser_network',
      'List browser network requests (devtools).',
      {
        filter: z.string().optional(),
        type: z.string().optional(),
        limit: z.number().int().positive().optional()
      },
      async (args) => callHalTool('hal_browser_network', args, context)
    ),
    tool(
      'hal_self_update_personality',
      'Update a personality trait (rate-limited).',
      {
        trait: z.string(),
        new_value: z.number().min(0).max(1),
        reason: z.string()
      },
      async (args) => callHalTool('hal_self_update_personality', args, context)
    ),
    tool(
      'hal_self_update_preference',
      'Store a learned user preference.',
      {
        key: z.string(),
        value: z.any()
      },
      async (args) => callHalTool('hal_self_update_preference', args, context)
    ),
    tool(
      'hal_self_set_goal',
      'Create a new goal.',
      {
        title: z.string(),
        description: z.string().optional(),
        type: z.enum(['short_term', 'medium_term', 'long_term']).optional(),
        success_criteria: z.array(z.string()).optional(),
        target_date: z.string().optional(),
        parent_id: z.string().optional(),
        priority: z.number().int().min(0).max(100).optional()
      },
      async (args) => callHalTool('hal_self_set_goal', args, context)
    ),
    tool(
      'hal_self_update_goal',
      'Update goal progress or status.',
      {
        goal_id: z.string(),
        progress: z.number().min(0).max(1).optional(),
        status: z.enum(['active', 'paused', 'completed', 'abandoned']).optional(),
        summary: z.string().optional()
      },
      async (args) => callHalTool('hal_self_update_goal', args, context)
    ),
    tool(
      'hal_self_reflect',
      'Log a reflection/learning for self-improvement.',
      {
        type: z.string().optional(),
        observation: z.string(),
        impact: z.string().optional(),
        confidence: z.enum(['low', 'medium', 'high']).optional()
      },
      async (args) => callHalTool('hal_self_reflect', args, context)
    ),
    tool(
      'hal_get_self_status',
      'Get current self status (personality, goals, observations).',
      {
        include_personality: z.boolean().optional(),
        include_goals: z.boolean().optional(),
        include_observations: z.boolean().optional(),
        observation_limit: z.number().int().positive().optional()
      },
      async (args) => callHalTool('hal_get_self_status', args, context)
    ),
    tool(
      'hal_skill_run',
      'Run a configured skill from .claude/skills through HAL (skills-first execution boundary).',
      {
        skill: z.string(),
        input: z.string(),
        vars: z.record(z.string(), z.any()).optional(),
        project_path: z.string().optional(),
        working_dir: z.string().optional(),
        timeout_ms: z.number().int().positive().optional(),
        tool_args: z.record(z.string(), z.any()).optional(),
        approval_token: z.string().optional()
      },
      async (args) => callHalTool('hal_skill_run', args, context)
    )
  ];

  return createSdkMcpServer({ name: 'hal', version: '1.0.0', tools });
}

// Handle query command
async function handleQuery(cmd: Command): Promise<void> {
  const { id, prompt, options = {}, context = {} } = cmd;

  if (!prompt) {
    sendError(id, 'Missing required parameter: prompt');
    return;
  }

  try {
    const queryOptions: any = {};

    // Capture stderr for debugging
    queryOptions.stderr = (msg: string) => {
      console.error(`[SDK stderr]: ${msg}`);
    };

    // Set model (default to sonnet for cost efficiency)
    queryOptions.model = options.model || 'claude-sonnet-4-5-20250929';

    // Auto-allow HAL MCP tools so the SDK doesn't block on its own permission layer.
    // HAL itself will still enforce approval_token for codops-impacting actions.
    queryOptions.allowedTools = mergeAllowedTools(options.allowed_tools);

    // Resume session if provided (must be a non-empty string)
    if (options.resume && typeof options.resume === 'string' && options.resume.trim().length > 0) {
      queryOptions.resume = options.resume;
    }

    // Set system prompt if provided
    if (options.system_prompt) {
      queryOptions.systemPrompt = {
        type: 'preset',
        preset: 'claude_code',
        append: options.system_prompt
      };
    }

    // Attach HAL custom tools via an in-process SDK MCP server.
    // These tools call back into Elixir for execution.
    queryOptions.mcpServers = {
      hal: buildHalMcpServer(context)
    };

    // Collect response
    let sessionId: string | undefined;
    let resultText = '';
    const messages: SDKMessage[] = [];

    const response = sdkQuery({
      prompt,
      options: queryOptions
    });

    for await (const msg of response) {
      messages.push(msg);

      // Capture session ID from init message
      if (msg.type === 'system' && msg.subtype === 'init') {
        sessionId = msg.session_id;
        // Track session
        if (sessionId) {
          activeSessions.set(sessionId, { lastUsed: Date.now() });
        }
      }

      // Capture text from assistant messages
      const text = extractTextFromMessage(msg);
      if (text) {
        resultText = text; // Use last assistant response as result
      }

      // Check for result message
      if ('result' in msg && typeof msg.result === 'string') {
        resultText = msg.result;
      }
    }

    sendResponse({
      id,
      success: true,
      result: resultText,
      session_id: sessionId
    });

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    sendError(id, `Query failed: ${errorMessage}`);
  }
}

// Handle create_session command (mostly for pre-warming)
async function handleCreateSession(cmd: Command): Promise<void> {
  const { id } = cmd;

  // Session creation is implicit - we just return success
  // The actual session is created when the first query is made
  const sessionId = `session-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  activeSessions.set(sessionId, { lastUsed: Date.now() });

  sendResponse({
    id,
    success: true,
    session_id: sessionId
  });
}

// Handle close_session command
async function handleCloseSession(cmd: Command): Promise<void> {
  const { id, session_id } = cmd;

  if (session_id) {
    activeSessions.delete(session_id);
  }

  sendResponse({
    id,
    success: true
  });
}

// Handle ping command
function handlePing(cmd: Command): void {
  sendResponse({
    id: cmd.id,
    success: true,
    result: 'pong'
  });
}

// Process a single command
async function processCommand(line: string): Promise<void> {
  let cmd: Command;

  try {
    cmd = JSON.parse(line);
  } catch {
    // Can't parse - send error with generic ID
    sendResponse({
      id: 'unknown',
      success: false,
      error: `Invalid JSON: ${line.substring(0, 100)}`
    });
    return;
  }

  const { command } = cmd;

  switch (command) {
    case 'query':
      await handleQuery(cmd);
      break;

    case 'create_session':
      await handleCreateSession(cmd);
      break;

    case 'close_session':
      await handleCloseSession(cmd);
      break;

    case 'ping':
      handlePing(cmd);
      break;

    case 'hal_tool_result': {
      const pending = pendingToolCalls.get(cmd.id);
      if (pending) {
        clearTimeout(pending.timer);
        pendingToolCalls.delete(cmd.id);
        pending.resolve(cmd);
      }
      break;
    }

    case 'shutdown':
      sendResponse({ id: cmd.id, success: true, result: 'shutting down' });
      process.exit(0);
      break;

    default:
      sendError(cmd.id, `Unknown command: ${command}`);
  }
}

// Cleanup old sessions periodically
function cleanupSessions(): void {
  const now = Date.now();
  for (const [sessionId, session] of activeSessions) {
    if (now - session.lastUsed > SESSION_TIMEOUT) {
      activeSessions.delete(sessionId);
    }
  }
}

// Main entry point
function main(): void {
  // Set up session cleanup interval
  setInterval(cleanupSessions, 60 * 1000); // Check every minute

  // Read commands from stdin
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false
  });

  rl.on('line', async (line) => {
    const trimmed = line.trim();
    if (trimmed) {
      await processCommand(trimmed);
    }
  });

  rl.on('close', () => {
    // Stdin closed - exit cleanly
    process.exit(0);
  });

  // Handle uncaught errors
  process.on('uncaughtException', (error) => {
    sendResponse({
      id: 'system',
      success: false,
      error: `Uncaught exception: ${error.message}`
    });
  });

  process.on('unhandledRejection', (reason) => {
    sendResponse({
      id: 'system',
      success: false,
      error: `Unhandled rejection: ${reason}`
    });
  });

  // Signal that we're ready
  sendResponse({
    id: 'init',
    success: true,
    result: 'HAL Agent SDK Bridge ready'
  });
}

main();
