"""
Claude Agent SDK wrapper for ErlPort integration.

This module provides a Python bridge between Elixir and the Claude Agent SDK.
ErlPort will call functions in this module to interact with Claude.

IMPORTANT: This uses your Claude subscription (Pro/Max) via OAuth token
from ~/.claude/.credentials.json, NOT the Anthropic API key.
"""

import asyncio
import os
import sys
from typing import List, Dict, Any, Optional

try:
    from claude_agent_sdk import query, ClaudeAgentOptions, ClaudeSDKClient
except ImportError:
    # Fallback if SDK not installed
    print("WARNING: claude-agent-sdk not installed. Please run: pip install claude-agent-sdk")
    query = None
    ClaudeAgentOptions = None
    ClaudeSDKClient = None


# Global state
_working_dir = None
_initialized = False
_auth_configured = False

# Client pool for session management (Phase 2)
_client_pool = {}  # Dict[session_id: str, client: ClaudeSDKClient]


def _erlport_to_string(value):
    """
    Convert ErlPort charlist/bytes to Python string.

    ErlPort passes Elixir strings as:
    - charlists (list of unicode codepoints) - use chr() for each
    - bytes - decode as utf-8

    IMPORTANT: bytes() fails for codepoints > 255, so we use chr() instead.
    """
    if value is None or value == 'undefined':
        return None
    if isinstance(value, list):
        # Charlist: list of unicode codepoints (can be > 255)
        return ''.join(chr(c) for c in value)
    elif isinstance(value, bytes):
        return value.decode('utf-8')
    return str(value) if not isinstance(value, str) else value


def _configure_auth() -> None:
    """
    Configure authentication to use Claude subscription OAuth token.

    IMPORTANT: Elixir already passes CLAUDE_CODE_OAUTH_TOKEN via ErlPort env.
    This function just validates it's set and removes ANTHROPIC_API_KEY if present
    (since API key takes priority over subscription token).
    """
    global _auth_configured

    if _auth_configured:
        return

    # Remove API key if set (so subscription token takes priority)
    if "ANTHROPIC_API_KEY" in os.environ:
        print("WARNING: Removing ANTHROPIC_API_KEY to use Claude subscription instead")
        del os.environ["ANTHROPIC_API_KEY"]

    # Verify OAuth token is set (should be passed from Elixir via ErlPort)
    oauth_token = os.environ.get('CLAUDE_CODE_OAUTH_TOKEN')

    if not oauth_token:
        raise EnvironmentError(
            "CLAUDE_CODE_OAUTH_TOKEN not set. "
            "This should be passed from Elixir via ErlPort. "
            "If running standalone, ensure Claude Code is authenticated: claude setup-token"
        )

    print(f"✓ Using Claude subscription (OAuth token set)")

    _auth_configured = True


def init(working_dir = ".") -> str:
    """
    Initialize the Claude agent with working directory.

    Called from Elixir via ErlPort.

    Args:
        working_dir: Directory where agent should operate (str or charlist from Elixir)

    Returns:
        Status message
    """
    global _working_dir, _initialized

    # Validate Python version (SDK requires 3.8+)
    if sys.version_info < (3, 8):
        return f"ERROR: Python 3.8+ required, got {sys.version_info.major}.{sys.version_info.minor}"

    # ErlPort passes Elixir strings as charlists (Python lists)
    # Convert to string if needed
    working_dir = _erlport_to_string(working_dir) or "."

    _working_dir = os.path.abspath(working_dir)

    # Configure authentication using Claude subscription
    try:
        _configure_auth()
    except Exception as e:
        return f"ERROR: Failed to configure authentication: {e}"

    _initialized = True

    # Verify Claude Code CLI is available
    if not os.path.exists(_working_dir):
        return f"ERROR: Working directory does not exist: {_working_dir}"

    return f"initialized:{_working_dir}"


def prompt(message, allowed_tools = None, custom_tools = None, base_system_prompt = None) -> List[Dict[str, Any]]:
    """
    Send a prompt to Claude Agent SDK and collect all results.

    This is a synchronous wrapper around the async query() function.
    ErlPort calls this function from Elixir.

    Args:
        message: The prompt/task for Claude (str or charlist)
        allowed_tools: Optional list of tools Claude can use
                      (e.g., ["Read", "Edit", "Bash", "Grep"])
        custom_tools: Optional list of custom tool definitions
                     (e.g., model delegation tools)
        base_system_prompt: Optional base system prompt to establish agent identity
                           and context (str or charlist)

    Returns:
        List of message dictionaries from Claude
    """
    if not _initialized:
        init()

    if query is None or ClaudeAgentOptions is None:
        return [{"error": "claude-agent-sdk not installed"}]

    # Convert charlist to string if needed
    message = _erlport_to_string(message)

    # Convert base_system_prompt if needed (ErlPort passes Elixir strings as bytes/charlist)
    base_system_prompt = _erlport_to_string(base_system_prompt)

    # Default tools if not specified or undefined
    if allowed_tools is None or allowed_tools == 'undefined':
        allowed_tools = ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
    else:
        # Convert each tool from charlist to string
        allowed_tools = [_erlport_to_string(t) or t for t in allowed_tools]

    # NOTE: We don't add model delegation tools to allowed_tools
    # because the SDK doesn't recognize them as built-in tools.
    # Instead, we tell Claude about them via system_prompt and let
    # the Elixir session layer intercept calls in the raw messages.

    # Parse custom tools if provided
    if custom_tools and custom_tools != 'undefined':
        custom_tools = _parse_custom_tools(custom_tools)

    # Run async function synchronously
    try:
        return asyncio.run(_prompt_async(message, allowed_tools, custom_tools, base_system_prompt))
    except Exception as e:
        return [{"error": str(e), "type": "exception"}]


async def _query_with_client_async(
    session_id: str,
    message: str,
    allowed_tools: List[str],
    custom_tools: Optional[List[Dict]] = None,
    base_system_prompt: Optional[str] = None
) -> List[Dict[str, Any]]:
    """
    Query using a persistent ClaudeSDKClient from the pool.

    This maintains conversation continuity within the SDK.
    """
    if session_id not in _client_pool:
        raise ValueError(f"Client not found for session {session_id}. Call create_client first.")

    client = _client_pool[session_id]
    messages = []

    try:
        # Build system prompt (same as current implementation)
        tool_system_prompt = _build_system_prompt(custom_tools)

        if base_system_prompt and tool_system_prompt:
            system_prompt = f"{base_system_prompt}\n\n{tool_system_prompt}"
        elif base_system_prompt:
            system_prompt = base_system_prompt
        else:
            system_prompt = tool_system_prompt

        # Configure client before querying
        # The client maintains these settings across calls
        await client.set_permission_mode("bypassPermissions")

        # Update client options with current settings
        client.options.allowed_tools = allowed_tools
        client.options.cwd = _working_dir
        if system_prompt:
            client.options.system_prompt = system_prompt

        # Start the query - this initiates the conversation
        await client.query(prompt=message)

        # Receive messages from the conversation
        async for msg in client.receive_messages():
            msg_dict = _serialize_message(msg)
            messages.append(msg_dict)

    except Exception as e:
        messages.append({
            "type": "error",
            "error": str(e),
            "traceback": str(e.__traceback__)
        })

    return messages


def query_with_client(
    session_id: str,
    message: str,
    allowed_tools: Optional[List[str]] = None,
    custom_tools: Optional[List[Dict]] = None,
    base_system_prompt: Optional[str] = None
) -> List[Dict[str, Any]]:
    """
    Send a prompt using a persistent ClaudeSDKClient.

    Called from Elixir via ErlPort.
    """
    if not _initialized:
        init()

    # Convert charlist to string
    if isinstance(session_id, list):
        session_id = _erlport_to_string(session_id)
    if isinstance(message, list):
        message = _erlport_to_string(message)

    # Handle base_system_prompt
    if base_system_prompt and base_system_prompt != 'undefined':
        try:
            if hasattr(base_system_prompt, 'decode'):
                base_system_prompt = base_system_prompt.decode('utf-8')
        except Exception as e:
            print(f"Warning: Failed to convert base_system_prompt: {e}")
            base_system_prompt = None
    else:
        base_system_prompt = None

    # Default tools
    if allowed_tools is None or allowed_tools == 'undefined':
        allowed_tools = ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
    else:
        allowed_tools = [_erlport_to_string(t) or t for t in allowed_tools]

    # Parse custom tools
    if custom_tools and custom_tools != 'undefined':
        custom_tools = _parse_custom_tools(custom_tools)

    # Run async function
    try:
        return asyncio.run(
            _query_with_client_async(
                session_id,
                message,
                allowed_tools,
                custom_tools,
                base_system_prompt
            )
        )
    except Exception as e:
        return [{"error": str(e), "type": "exception"}]


async def _prompt_async(message: str, allowed_tools: List[str], custom_tools: Optional[List[Dict]] = None, base_system_prompt: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Async implementation of prompt().

    Collects all messages from the Claude Agent SDK stream.
    """
    messages = []

    try:
        # Build tool delegation system prompt (for gemini, codex, jules tools)
        tool_system_prompt = _build_system_prompt(custom_tools)

        # Combine base system prompt (identity + context) with tool system prompt
        if base_system_prompt and tool_system_prompt:
            system_prompt = f"{base_system_prompt}\n\n{tool_system_prompt}"
        elif base_system_prompt:
            system_prompt = base_system_prompt
        else:
            system_prompt = tool_system_prompt

        options = ClaudeAgentOptions(
            allowed_tools=allowed_tools,
            permission_mode="bypassPermissions",  # Auto-approve tools
            cwd=_working_dir,
            system_prompt=system_prompt if system_prompt else None
        )

        async for msg in query(prompt=message, options=options):
            # Convert message to serializable dict
            msg_dict = _serialize_message(msg)
            messages.append(msg_dict)

    except Exception as e:
        messages.append({
            "type": "error",
            "error": str(e),
            "traceback": str(e.__traceback__)
        })

    return messages


def prompt_streaming(message: str, allowed_tools: Optional[List[str]] = None):
    """
    Stream responses from Claude (for future use).

    Currently not used - ErlPort doesn't handle generators well.
    We collect all messages and return them at once via prompt().
    """
    if not _initialized:
        init()

    if allowed_tools is None:
        allowed_tools = ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]

    # For streaming, we'd need to use ErlPort's message handler
    # For now, use the synchronous prompt() function
    return prompt(message, allowed_tools)


def _serialize_message(msg: Any) -> Dict[str, Any]:
    """
    Convert Claude SDK message to ErlPort-compatible dict.

    ErlPort can serialize: strings, ints, floats, lists, tuples, dicts, booleans.
    """
    # If it's already a dict, return it
    if isinstance(msg, dict):
        return msg

    # If it has __dict__, convert it
    if hasattr(msg, '__dict__'):
        obj_dict = {}
        for key, value in msg.__dict__.items():
            # Skip private attributes
            if key.startswith('_'):
                continue
            # Recursively serialize nested objects
            obj_dict[key] = _serialize_value(value)
        return obj_dict

    # Otherwise, convert to string representation
    return {"value": str(msg), "type": type(msg).__name__}


def _serialize_value(value: Any) -> Any:
    """
    Recursively serialize values for ErlPort compatibility.
    """
    if value is None:
        return None
    elif isinstance(value, (str, int, float, bool)):
        return value
    elif isinstance(value, (list, tuple)):
        return [_serialize_value(item) for item in value]
    elif isinstance(value, dict):
        return {k: _serialize_value(v) for k, v in value.items()}
    elif hasattr(value, '__dict__'):
        return _serialize_message(value)
    else:
        return str(value)


def _parse_custom_tools(custom_tools: Any) -> List[Dict[str, Any]]:
    """
    Parse custom tools from ErlPort format to Python dicts.

    Args:
        custom_tools: Custom tools from Elixir (may be charlist or dict)

    Returns:
        List of tool definition dicts
    """
    if not custom_tools:
        return []

    # If it's already a list of dicts, return it
    if isinstance(custom_tools, list):
        return [_convert_tool_dict(tool) for tool in custom_tools]

    return []


def _convert_tool_dict(tool: Any) -> Dict[str, Any]:
    """
    Convert a tool definition from ErlPort format to standard dict.

    Handles charlist keys and values from Elixir.
    """
    if isinstance(tool, dict):
        return tool

    # Handle ErlPort list of tuples (keyword list from Elixir)
    if isinstance(tool, list):
        result = {}
        for item in tool:
            if isinstance(item, tuple) and len(item) == 2:
                key, value = item
                # Convert charlist key to string
                if isinstance(key, list):
                    key = _erlport_to_string(key)
                elif isinstance(key, bytes):
                    key = key.decode('utf-8')

                # Convert charlist value to string
                if isinstance(value, list) and all(isinstance(x, int) for x in value):
                    value = _erlport_to_string(value)
                elif isinstance(value, bytes):
                    value = value.decode('utf-8')
                elif isinstance(value, dict) or isinstance(value, list):
                    value = _convert_tool_dict(value)

                result[str(key)] = value
        return result

    return {}


def get_model_tools() -> List[Dict[str, Any]]:
    """
    Get the list of model delegation tools that Claude can use.

    These tools allow Claude to delegate tasks to other models:
    - gemini: Fast, cheap model for simple queries
    - codex: Code generation specialist
    - jules: Async background tasks

    Returns:
        List of tool definitions in Claude SDK format
    """
    return [
        {
            "name": "gemini",
            "description": """Fast, cheap model for simple queries. Cost: $0.15/1M tokens (400x cheaper than me!).

BEST FOR:
- File operations (list, find, count)
- Simple lookups or searches
- Quick responses needed
- Cost-sensitive queries

WHEN TO USE:
- \"List all .ex files\"
- \"How many tests do we have?\"
- \"Find files containing 'TODO'\"
- \"Count lines in this file\"

DO NOT USE FOR:
- Complex reasoning
- Architecture decisions
- Code refactoring
- Writing code""",
            "input_schema": {
                "type": "object",
                "properties": {
                    "prompt": {
                        "type": "string",
                        "description": "The query to send to Gemini. Keep it simple and direct."
                    }
                },
                "required": ["prompt"]
            }
        },
        {
            "name": "codex",
            "description": """Code generation specialist. Cost: $15/1M tokens (4x cheaper than me).

BEST FOR:
- Generating new code (functions, classes, modules)
- Implementing features or functionality
- Writing tests
- Fixing bugs with code changes

WHEN TO USE:
- \"Write a function to parse JSON\"
- \"Implement user authentication\"
- \"Create tests for this module\"
- \"Fix this bug in the code\"

DO NOT USE FOR:
- File searches
- Simple queries
- Architecture decisions
- Background tasks""",
            "input_schema": {
                "type": "object",
                "properties": {
                    "prompt": {
                        "type": "string",
                        "description": "The code generation task to send to Codex. Be specific about requirements."
                    }
                },
                "required": ["prompt"]
            }
        },
        {
            "name": "jules",
            "description": """Async background task specialist. Cost: $10/1M tokens (6x cheaper than me).

BEST FOR:
- Large refactoring across multiple files
- Long-running operations
- Tasks that can run in background
- Don't need immediate response

WHEN TO USE:
- \"Refactor all controllers to use new pattern\"
- \"Migrate database schema\"
- \"Update all tests to use new API\"
- \"Large codebase cleanup\"

DO NOT USE FOR:
- Quick queries
- Interactive tasks
- Urgent requests
- Simple operations

NOTE: Jules works in background. Results arrive later via callback.""",
            "input_schema": {
                "type": "object",
                "properties": {
                    "prompt": {
                        "type": "string",
                        "description": "The background task to send to Jules. Should be a self-contained task."
                    }
                },
                "required": ["prompt"]
            }
        }
    ]


def _build_system_prompt(custom_tools: Optional[List[Dict]] = None) -> Optional[str]:
    """
    Build system prompt that includes information about model delegation tools.

    Args:
        custom_tools: Optional list of custom tool definitions to include

    Returns:
        System prompt string or None if no custom tools
    """
    if not custom_tools:
        custom_tools = get_model_tools()

    if not custom_tools:
        return None

    tool_descriptions = []
    for tool in custom_tools:
        name = tool.get("name", "unknown")
        desc = tool.get("description", "")
        tool_descriptions.append(f"- **{name}**: {desc}")

    tools_text = "\n".join(tool_descriptions)

    return f"""You have access to additional model delegation tools for cost optimization:

{tools_text}

IMPORTANT: To use these tools, you can call them just like any other tool using tool_use blocks.
The system will intercept these calls and route them to the appropriate model.

Example:
<tool_use>
  <tool>gemini</tool>
  <input>
    <prompt>List all Python files in the current directory</prompt>
  </input>
</tool_use>

Use these tools strategically to minimize costs while maintaining quality."""


def create_client(session_id: str) -> Dict[str, Any]:
    """
    Create or retrieve a ClaudeSDKClient for a specific session.

    Args:
        session_id: Unique identifier (charlist from ErlPort)

    Returns:
        Status dict with client info
    """
    # Convert charlist to string if needed
    if isinstance(session_id, list):
        session_id = _erlport_to_string(session_id)

    if session_id in _client_pool:
        return {
            "status": "reused",
            "session_id": session_id,
            "message": f"Reused existing client for session {session_id}"
        }

    try:
        # Create new ClaudeSDKClient instance and connect
        client = ClaudeSDKClient()

        # Connect the client (async operation, run in event loop)
        asyncio.run(client.connect())

        _client_pool[session_id] = client

        return {
            "status": "created",
            "session_id": session_id,
            "message": f"Created new client for session {session_id}"
        }
    except Exception as e:
        return {
            "status": "error",
            "session_id": session_id,
            "error": str(e)
        }


def close_client(session_id: str) -> Dict[str, Any]:
    """
    Clean up a client from the pool when session terminates.

    Args:
        session_id: Session ID (charlist from Elixir)

    Returns:
        Status dict
    """
    if isinstance(session_id, list):
        session_id = _erlport_to_string(session_id)

    if session_id not in _client_pool:
        return {
            "status": "not_found",
            "session_id": session_id,
            "message": f"No client found for session {session_id}"
        }

    try:
        client = _client_pool.pop(session_id)

        # Disconnect the client (async operation)
        if hasattr(client, 'disconnect'):
            asyncio.run(client.disconnect())

        return {
            "status": "closed",
            "session_id": session_id,
            "message": f"Closed client for session {session_id}"
        }
    except Exception as e:
        return {
            "status": "error",
            "session_id": session_id,
            "error": str(e)
        }


def get_client_status(session_id: str) -> Dict[str, Any]:
    """
    Get status of a client in the pool (for debugging).

    Args:
        session_id: Session ID (charlist from Elixir)

    Returns:
        Status dict
    """
    if isinstance(session_id, list):
        session_id = _erlport_to_string(session_id)

    if session_id not in _client_pool:
        return {"status": "not_found", "session_id": session_id}

    client = _client_pool[session_id]

    return {
        "status": "active",
        "session_id": session_id,
        "client_type": type(client).__name__
    }


def get_status() -> Dict[str, Any]:
    """
    Get current agent status including SDK availability.

    Returns:
        Status information dict
    """
    auth_method = None
    if os.getenv('CLAUDE_CODE_OAUTH_TOKEN'):
        auth_method = 'oauth_subscription'
    elif os.getenv('ANTHROPIC_API_KEY'):
        auth_method = 'api_key'

    return {
        "initialized": _initialized,
        "working_dir": _working_dir,
        "sdk_available": query is not None and ClaudeAgentOptions is not None,
        "auth_configured": _auth_configured,
        "auth_method": auth_method,
        "python_version": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        "client_pool_size": len(_client_pool)
    }


# Module-level test function
def test_connection() -> str:
    """
    Test that ErlPort can call this module.

    Returns:
        Success message
    """
    return "claude_agent.py: connection successful"


if __name__ == "__main__":
    # Test the module locally
    print("Testing claude_agent.py...")
    print(f"Status: {get_status()}")

    # Test init (will configure OAuth token from ~/.claude/.credentials.json)
    result = init("/Users/chrisohalloran/dev/concepts/agent_gateway")
    print(f"Init: {result}")

    # Test simple prompt (uses Claude subscription)
    if _auth_configured:
        print("\nTesting prompt with Claude subscription...")
        messages = prompt("What files are in the current directory?", ["Bash", "Read"])
        print(f"Received {len(messages)} messages")

        # Find result message
        for msg in messages:
            if isinstance(msg, dict) and "result" in msg:
                print(f"Result: {msg['result']}")
    else:
        print("Skipping prompt test (authentication not configured)")
