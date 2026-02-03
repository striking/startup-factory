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

import { createInterface } from 'readline';
import { Codex } from '@openai/codex-sdk';

// Type definitions
interface Command {
  id: string;
  command: 'start_thread' | 'run' | 'resume_thread' | 'list_threads' | 'ping' | 'shutdown';
  thread_id?: string;
  prompt?: string;
  project_path?: string;
  options?: RunOptions;
}

interface RunOptions {
  model?: string;
  timeout?: number;
}

interface Response {
  id: string;
  success: boolean;
  result?: string;
  thread_id?: string;
  error?: string;
}

// Codex instance and active threads
let codex: Codex | null = null;
const activeThreads = new Map<string, ReturnType<Codex['startThread']>>();

// Send a response back to Elixir
function sendResponse(response: Response): void {
  console.log(JSON.stringify(response));
}

// Send an error response
function sendError(id: string, error: string): void {
  sendResponse({ id, success: false, error });
}

// Initialize Codex client
function initCodex(): Codex {
  if (!codex) {
    codex = new Codex();
  }
  return codex;
}

// Handle start_thread command
async function handleStartThread(cmd: Command): Promise<void> {
  const { id, project_path, options = {} } = cmd;

  try {
    const client = initCodex();
    const workingDirectory = project_path || process.cwd();

    // Default safety posture: allow workspace writes, no interactive approvals
    // (human approval is handled in HAL before delegation).
    const thread = client.startThread({
      workingDirectory,
      sandboxMode: "workspace-write",
      approvalPolicy: "never",
      ...(options.model ? { model: options.model } : {})
    });

    // Generate a unique thread ID
    const threadId = `thread-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    activeThreads.set(threadId, thread);

    sendResponse({
      id,
      success: true,
      thread_id: threadId,
      result: 'Thread created'
    });

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    sendError(id, `Failed to start thread: ${errorMessage}`);
  }
}

// Handle run command
async function handleRun(cmd: Command): Promise<void> {
  const { id, thread_id, prompt, options = {} } = cmd;

  if (!thread_id) {
    sendError(id, 'Missing required parameter: thread_id');
    return;
  }

  if (!prompt) {
    sendError(id, 'Missing required parameter: prompt');
    return;
  }

  const thread = activeThreads.get(thread_id);
  if (!thread) {
    sendError(id, `Thread not found: ${thread_id}`);
    return;
  }

  try {
    // Run the prompt on the thread
    const turn = await thread.run(prompt);
    const actualThreadId = thread.id || thread_id;

    // If Codex assigned a durable thread id, update our in-memory handle so
    // subsequent calls (and Elixir session persistence) can use it.
    if (actualThreadId !== thread_id && !activeThreads.has(actualThreadId)) {
      activeThreads.delete(thread_id);
      activeThreads.set(actualThreadId, thread);
    }

    sendResponse({
      id,
      success: true,
      thread_id: actualThreadId,
      result: turn.finalResponse
    });

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    sendError(id, `Run failed: ${errorMessage}`);
  }
}

// Handle resume_thread command
async function handleResumeThread(cmd: Command): Promise<void> {
  const { id, thread_id } = cmd;

  if (!thread_id) {
    sendError(id, 'Missing required parameter: thread_id (Codex session ID to resume)');
    return;
  }

  try {
    const client = initCodex();
    const thread = client.resumeThread(thread_id);

    // Store with the original Codex thread ID
    activeThreads.set(thread_id, thread);

    sendResponse({
      id,
      success: true,
      thread_id,
      result: 'Thread resumed'
    });

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    sendError(id, `Failed to resume thread: ${errorMessage}`);
  }
}

// Handle list_threads command
function handleListThreads(cmd: Command): void {
  const threadIds = Array.from(activeThreads.keys());

  sendResponse({
    id: cmd.id,
    success: true,
    result: JSON.stringify(threadIds)
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
    sendResponse({
      id: 'unknown',
      success: false,
      error: `Invalid JSON: ${line.substring(0, 100)}`
    });
    return;
  }

  const { command } = cmd;

  switch (command) {
    case 'start_thread':
      await handleStartThread(cmd);
      break;

    case 'run':
      await handleRun(cmd);
      break;

    case 'resume_thread':
      await handleResumeThread(cmd);
      break;

    case 'list_threads':
      handleListThreads(cmd);
      break;

    case 'ping':
      handlePing(cmd);
      break;

    case 'shutdown':
      sendResponse({ id: cmd.id, success: true, result: 'shutting down' });
      process.exit(0);
      break;

    default:
      sendError(cmd.id, `Unknown command: ${command}`);
  }
}

// Main entry point
function main(): void {
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
    result: 'HAL Codex SDK Bridge ready'
  });
}

main();
