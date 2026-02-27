# PRD: Agent Email Integration

## Introduction

Give the love.Me AI agent its own email capabilities by connecting a Gmail/Outlook account. When the agent receives an email, it creates a conversation, can trigger workflows, reply via email, and use MCP tools to act on the content. The architecture is hybrid: the daemon handles email ingestion and monitoring, while a dedicated Email MCP server exposes email actions (send, search, reply) as tools Claude can use during any conversation.

This turns the agent from a chat-only assistant into an always-available agent that can receive tasks, information, and requests via email — then act on them using its full toolkit.

## Goals

- Connect a Gmail or Outlook account via OAuth2 so the agent has a real email address
- Poll for new emails and automatically create conversations from them
- Allow Claude to reply to emails, forward information, and search the mailbox via MCP tools
- Trigger existing workflows based on email content (subject line rules, sender rules, keyword matching)
- Handle all email content: text, HTML, attachments (PDFs, images, docs), links, and calendar invites
- Surface email-linked conversations in the iOS app with clear email origin indicators
- Keep email credentials secure (OAuth2 tokens in keychain/encrypted storage, never in plaintext config)

## User Stories

### US-001: Email OAuth2 Configuration Storage
**Description:** As a developer, I need to store email provider configuration and OAuth2 tokens so the daemon can authenticate with Gmail/Outlook APIs.

**Acceptance Criteria:**
- [ ] Add `EmailConfig` model with fields: provider (gmail/outlook), clientId, clientSecret, refreshToken, accessToken, tokenExpiry, emailAddress, pollingIntervalSeconds
- [ ] Add `EmailConfigStore` that reads/writes `~/.love-me/email.json`
- [ ] Tokens are stored with file permissions 0600 (owner-only read/write)
- [ ] Store supports token refresh — updating accessToken and tokenExpiry without losing other fields
- [ ] Typecheck passes

### US-002: Gmail OAuth2 Token Exchange
**Description:** As a user, I want to authenticate my Gmail account so the agent can read and send emails on my behalf.

**Acceptance Criteria:**
- [ ] Add `GmailAuthService` that implements OAuth2 authorization code flow
- [ ] Daemon exposes a WebSocket message `email_auth_start` that returns an OAuth2 authorization URL
- [ ] Daemon exposes a local HTTP callback endpoint (e.g., `localhost:9477/oauth/callback`) to receive the auth code
- [ ] After receiving the auth code, exchanges it for access + refresh tokens via Google's token endpoint
- [ ] Stores tokens via `EmailConfigStore`
- [ ] Daemon sends `email_auth_complete` WebSocket message with the connected email address
- [ ] Typecheck passes

### US-003: Gmail API Client — Read Emails
**Description:** As a developer, I need a Gmail API client that can fetch emails so the daemon can poll for new messages.

**Acceptance Criteria:**
- [ ] Add `GmailClient` with methods: `listMessages(query:maxResults:pageToken:)`, `getMessage(id:)`, `getAttachment(messageId:attachmentId:)`
- [ ] Automatic token refresh when accessToken is expired (using refreshToken)
- [ ] `getMessage` returns parsed `EmailMessage` model with: id, threadId, from, to, cc, subject, bodyText, bodyHtml, attachments (metadata), receivedAt, labels
- [ ] `EmailAttachment` model with: id, filename, mimeType, size
- [ ] Attachment content fetched lazily (not downloaded until requested)
- [ ] Handles Gmail API pagination via nextPageToken
- [ ] Typecheck passes

### US-004: Gmail API Client — Send & Reply
**Description:** As a developer, I need the Gmail client to send and reply to emails so Claude can respond via email.

**Acceptance Criteria:**
- [ ] Add `sendEmail(to:subject:body:cc:bcc:attachments:)` method to `GmailClient`
- [ ] Add `replyToEmail(messageId:threadId:body:)` method that sets proper In-Reply-To and References headers
- [ ] Email body supports both plain text and HTML
- [ ] Attachments sent as base64-encoded MIME parts
- [ ] Returns the sent message ID on success
- [ ] Typecheck passes

### US-005: Email Polling Service
**Description:** As a user, I want the daemon to automatically check for new emails so the agent can act on incoming messages without manual intervention.

**Acceptance Criteria:**
- [ ] Add `EmailPollingService` that runs on a configurable interval (default: 60 seconds)
- [ ] Tracks last-seen email ID/timestamp to only fetch new messages since last poll
- [ ] Persists last-seen marker to `~/.love-me/email-state.json` so it survives daemon restarts
- [ ] On new email: emits `EventBus.emailReceived(EmailMessage)` event
- [ ] Starts automatically on daemon launch if email is configured
- [ ] Logs poll results (count of new emails, or "no new emails") at debug level
- [ ] Gracefully handles API errors (rate limits, auth failures) with exponential backoff
- [ ] Typecheck passes

### US-006: Email-to-Conversation Bridge
**Description:** As a user, I want incoming emails to automatically create conversations so the agent can process and respond to them.

**Acceptance Criteria:**
- [ ] `EmailConversationBridge` listens for `EventBus.emailReceived` events
- [ ] Creates a new conversation via `ConversationStore` with title set to email subject
- [ ] First message in conversation is a system-formatted email summary: sender, subject, body (truncated to 4000 chars), attachment list, received time
- [ ] Conversation metadata includes `sourceType: "email"`, `emailThreadId`, `emailMessageId`, `fromAddress`
- [ ] Automatically sends the conversation to Claude for processing (same flow as user sending a chat message)
- [ ] Claude's response is stored in the conversation AND sent as an email reply (via GmailClient.replyToEmail)
- [ ] Subsequent emails in the same thread append to the existing conversation instead of creating a new one (matched by threadId)
- [ ] Typecheck passes

### US-007: Email MCP Server — Core Tools
**Description:** As Claude, I need email tools available via MCP so I can send emails, search the mailbox, and read specific messages during any conversation.

**Acceptance Criteria:**
- [ ] Create `EmailMCPServer` as a new stdio-based MCP server (within the daemon, not a separate process)
- [ ] Exposes tool `send_email` with params: to, subject, body, cc (optional), bcc (optional)
- [ ] Exposes tool `reply_to_email` with params: emailMessageId, body
- [ ] Exposes tool `search_emails` with params: query (Gmail search syntax), maxResults (default 10)
- [ ] Exposes tool `get_email` with params: emailMessageId — returns full email content
- [ ] Exposes tool `get_attachment` with params: emailMessageId, attachmentId — returns attachment content (text extracted for PDFs/docs, base64 for images capped at 4KB summary)
- [ ] Tools registered with MCPManager so they appear in Claude's tool list alongside other MCP tools
- [ ] Typecheck passes

### US-008: Email-to-Workflow Trigger Rules
**Description:** As a user, I want to define rules that automatically trigger workflows when emails match certain criteria.

**Acceptance Criteria:**
- [ ] Add `EmailTriggerRule` model with fields: id, workflowId, conditions (fromContains, subjectContains, bodyContains, hasAttachment, labelEquals), enabled
- [ ] Add `EmailTriggerStore` that reads/writes rules from `~/.love-me/email-triggers.json`
- [ ] `EmailConversationBridge` evaluates trigger rules on each incoming email
- [ ] When a rule matches, executes the linked workflow with email data as input (sender, subject, body, attachmentIds)
- [ ] Multiple rules can match the same email (all matching workflows execute)
- [ ] Trigger evaluation logged for debugging
- [ ] Typecheck passes

### US-009: Attachment Processing Pipeline
**Description:** As the agent, I need to extract usable content from email attachments so I can understand and act on documents, images, and files sent to me.

**Acceptance Criteria:**
- [ ] Add `AttachmentProcessor` that handles common MIME types
- [ ] PDF: extract text content (using system `pdftotext` or similar)
- [ ] Images (jpg, png): store locally in `~/.love-me/attachments/`, provide file path to Claude
- [ ] Plain text / CSV / JSON: include content directly
- [ ] Calendar invites (.ics): parse event summary, date, time, location, attendees
- [ ] Other types: store file, provide filename and MIME type metadata only
- [ ] All processed attachments stored in `~/.love-me/attachments/{emailId}/`
- [ ] Large attachments (>10MB) skipped with a log warning
- [ ] Typecheck passes

### US-010: WebSocket Messages for Email Management
**Description:** As the iOS app, I need WebSocket messages to manage email configuration and view email-linked conversations.

**Acceptance Criteria:**
- [ ] `email_status` message: returns whether email is configured, connected email address, last poll time, total emails processed
- [ ] `email_auth_start` message: initiates OAuth2 flow, returns authorization URL
- [ ] `email_auth_disconnect` message: removes stored tokens, stops polling
- [ ] `email_triggers_list` message: returns all trigger rules
- [ ] `email_trigger_create` / `email_trigger_update` / `email_trigger_delete` messages for CRUD
- [ ] `email_poll_now` message: triggers an immediate poll (bypassing interval)
- [ ] All messages follow existing WebSocket message patterns in DaemonApp
- [ ] Typecheck passes

### US-011: iOS Email Settings View
**Description:** As a user, I want to connect and manage my email account from the iOS app.

**Acceptance Criteria:**
- [ ] Add `EmailSettingsView` accessible from app settings/profile
- [ ] Shows connection status: connected email address or "Not connected"
- [ ] "Connect Gmail" button that opens OAuth2 URL in Safari/SFSafariViewController
- [ ] "Disconnect" button with confirmation dialog
- [ ] Shows last poll time and emails processed count
- [ ] Polling interval selector (1min, 2min, 5min, 15min)
- [ ] Typecheck passes
- [ ] Verify changes work in browser

### US-012: iOS Email Trigger Rules View
**Description:** As a user, I want to create and manage email trigger rules from the iOS app so certain emails automatically run workflows.

**Acceptance Criteria:**
- [ ] Add `EmailTriggersView` showing list of all trigger rules
- [ ] Each rule shows: conditions summary, linked workflow name, enabled/disabled toggle
- [ ] "Add Rule" form with fields: from contains, subject contains, body contains, has attachment toggle, workflow picker
- [ ] Edit and delete existing rules
- [ ] Typecheck passes
- [ ] Verify changes work in browser

### US-013: Email Origin Indicator in Conversations
**Description:** As a user, I want to see which conversations originated from emails so I can distinguish them from regular chats.

**Acceptance Criteria:**
- [ ] Conversations with `sourceType: "email"` show an email icon badge in the conversation list
- [ ] Conversation detail view shows email metadata header: from address, subject, received time
- [ ] Tapping the email header shows full email details (all recipients, full body)
- [ ] Typecheck passes
- [ ] Verify changes work in browser

## Non-Goals

- **No multi-provider support in v1** — Gmail only initially; Outlook/IMAP can be added later using the same interfaces
- **No email drafts** — Claude sends emails immediately, no draft review flow
- **No email deletion or label management** — agent is read + reply only, not a full email client
- **No real-time push notifications from Gmail** — polling-based for simplicity; Google Pub/Sub push can be added later
- **No email forwarding to other people** — agent can only reply to threads it received, not forward to arbitrary addresses
- **No email-based authentication** — email is an input/output channel, not a login method

## Technical Considerations

- **OAuth2 redirect**: The daemon runs locally, so the OAuth2 callback needs a local HTTP server (similar to how CLI tools handle Google auth). Port should be configurable to avoid conflicts.
- **Gmail API scopes**: Need `gmail.readonly` + `gmail.send` + `gmail.modify` (for marking as read). Request minimal scopes.
- **Token refresh**: Gmail access tokens expire after 1 hour. The client must handle transparent refresh using the stored refresh token.
- **Rate limits**: Gmail API has a 250 quota units/second limit. Polling once per minute is well within limits.
- **Email MCP server as internal module**: Rather than spawning a separate process, the email MCP tools should be registered directly with MCPManager as "built-in" tools — this avoids process management overhead and gives direct access to GmailClient.
- **Attachment storage**: Use `~/.love-me/attachments/` with cleanup policy (delete after 30 days) to prevent unbounded disk usage.
- **Existing patterns to reuse**: WebSocket message handling (DaemonApp.swift), EventBus for decoupled events, ConversationStore for persistence, WorkflowExecutor for workflow triggering.
- **Thread matching**: Gmail provides threadId grouping — use this to append follow-up emails to existing conversations rather than creating duplicates.
