# HAL Integrations

This directory contains integration modules for external services used by HAL.

## Tasks Integration (Linear)

The `HAL.Integrations.Tasks` module provides integration with Linear's API for task management.

### Setup

1. Get your Linear API key from https://linear.app/settings/api

2. Add to your environment or runtime configuration:

```bash
export LINEAR_API_KEY="lin_api_xxxxxxxxxxxxx"
```

Or in `config/runtime.exs`:

```elixir
config :hal, HAL.Integrations.Tasks,
  api_key: System.get_env("LINEAR_API_KEY")
```

### Usage Examples

```elixir
alias HAL.Integrations.Tasks

# List all tasks for a team
{:ok, tasks} = Tasks.list_tasks(team_id: "your_team_id")

# List tasks with filters
{:ok, tasks} = Tasks.list_tasks(
  team_id: "your_team_id",
  assignee_id: "user_id",
  state: "In Progress",
  priority: 1,
  limit: 20
)

# Create a new task
{:ok, task} = Tasks.create_task(
  team_id: "your_team_id",
  title: "Implement new feature",
  description: "Add support for X",
  priority: 1
)

# Update a task
{:ok, task} = Tasks.update_task(
  "issue_id",
  title: "Updated title",
  priority: 2
)

# Mark task as complete
{:ok, task} = Tasks.complete_task("issue_id")
```

### Finding Your Team ID

You can find your team ID by inspecting the URL in Linear:
- URL format: `https://linear.app/YOUR_TEAM/...`
- Or use the Linear API to list teams

### API Reference

- [Linear GraphQL API Documentation](https://developers.linear.app/docs/graphql/working-with-the-graphql-api)
- [Linear API Explorer](https://studio.apollographql.com/public/Linear-API/explorer)

### Testing

The module includes comprehensive tests with mocked HTTP responses. Run tests with:

```bash
mix test test/hal/integrations/tasks_test.exs
```

## Email Integration (Gmail)

The `HAL.Integrations.Email` module provides integration with Gmail API for email operations.

### Status

OAuth token acquisition is marked as TODO. The module currently expects OAuth tokens to be passed directly to functions.

### Setup

1. **Create Google Cloud Project:**
   - Go to https://console.cloud.google.com/
   - Create a new project or select existing one
   - Enable the Gmail API

2. **Create OAuth 2.0 Credentials:**
   - Navigate to "APIs & Services" > "Credentials"
   - Click "Create Credentials" > "OAuth 2.0 Client ID"
   - Application type: Web application
   - Add authorized redirect URI: `http://localhost:4000/auth/gmail/callback`
   - Save the Client ID and Client Secret

3. **Configure Environment Variables:**

```bash
export GMAIL_CLIENT_ID="your_client_id_here"
export GMAIL_CLIENT_SECRET="your_client_secret_here"
export GMAIL_REDIRECT_URI="http://localhost:4000/auth/gmail/callback"
```

Or in `config/runtime.exs`:

```elixir
config :hal, HAL.Integrations.Email,
  client_id: System.get_env("GMAIL_CLIENT_ID"),
  client_secret: System.get_env("GMAIL_CLIENT_SECRET"),
  redirect_uri: System.get_env("GMAIL_REDIRECT_URI")
```

### Usage Examples

```elixir
alias HAL.Integrations.Email

# Note: You need to obtain an OAuth token first (implementation TODO)
token = "user_oauth_access_token"

# Get unread emails (default: 10 most recent)
{:ok, emails} = Email.get_unread_emails(token)

# Get unread emails with custom options
{:ok, emails} = Email.get_unread_emails(token,
  max_results: 50,
  query: "has:attachment"
)

# Send an email
{:ok, message} = Email.send_email(token,
  to: "recipient@example.com",
  subject: "Hello from HAL",
  body: "This is an automated message"
)

# Send email with CC and BCC
{:ok, message} = Email.send_email(token,
  to: "recipient@example.com",
  subject: "Team Update",
  body: "Here's the update...",
  cc: "team@example.com",
  bcc: "archive@example.com"
)

# Search emails with Gmail query syntax
{:ok, results} = Email.search_emails(
  token,
  "from:boss@company.com is:unread"
)

# Mark email as read
{:ok, _} = Email.mark_as_read(token, message_id)
```

### Gmail Search Query Syntax

The `search_emails/3` function supports Gmail's powerful search syntax:

| Query | Description |
|-------|-------------|
| `from:user@example.com` | Emails from specific sender |
| `to:user@example.com` | Emails to specific recipient |
| `subject:meeting` | Emails with "meeting" in subject |
| `has:attachment` | Emails with attachments |
| `is:unread` | Unread emails |
| `is:starred` | Starred emails |
| `label:important` | Emails with specific label |
| `after:2024/01/01` | Emails after date |
| `before:2024/12/31` | Emails before date |
| `older_than:7d` | Emails older than 7 days |
| `newer_than:2d` | Emails newer than 2 days |

Combine queries with spaces (implicit AND):

```elixir
# Unread emails from boss with attachments
Email.search_emails(token, "from:boss@company.com is:unread has:attachment")

# Important emails from this week
Email.search_emails(token, "label:important newer_than:7d")
```

### API Reference

- [Gmail API Documentation](https://developers.google.com/gmail/api)
- [Search Query Syntax](https://support.google.com/mail/answer/7190)

### TODO

- [ ] Implement OAuth 2.0 authorization flow
- [ ] Add token storage (encrypted in database)
- [ ] Implement token refresh mechanism
- [ ] Add automatic token expiration handling
- [ ] Create Phoenix controller for OAuth callback
- [ ] Add user consent flow
- [ ] Implement rate limiting
- [ ] Add retry logic with exponential backoff

### Testing

The module includes tests with mocked HTTP responses (currently skipped). Run tests with:

```bash
mix test test/hal/integrations/email_test.exs
```

To enable integration testing, see comments in the test file.

## Calendar Integration (Google Calendar)

The `HAL.Integrations.Calendar` module provides integration with Google Calendar API.

See the module documentation for setup and usage.

## Future Integrations

- Storage (Dropbox, Google Drive)
- Outlook Calendar/Email
- Notion
- Todoist
