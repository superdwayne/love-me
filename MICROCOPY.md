# love.Me — UX Microcopy Bible

Every word in this app is intentional. This is the single source of truth for all UI text.

---

## 1. Onboarding (3 Screens)

### Screen 1: Welcome
```
Headline:    love.Me
Subhead:     Your AI, working for you.
Body:        Tell me what you need. I'll do it on your Mac —
             and show you every step.
CTA:         Get Started
```

### Screen 2: Connect
```
Headline:    Connect to your Mac
Body:        I need a connection to your computer to get work done.
             Start the love.Me daemon on your Mac, then scan the
             QR code — or enter your details manually.
CTA:         Scan QR Code
Secondary:   Enter manually
```

### Screen 3: Ready
```
Headline:    You're connected.
Body:        Send me a message and I'll get to work.
             You can see my thinking and every tool I use.
CTA:         Start a conversation
```

---

## 2. Empty States

### No Conversations Yet (Conversation List)
```
Headline:    No conversations yet
Body:        Start one and I'll remember it for next time.
CTA:         New conversation
```

### New Conversation (Chat View — Empty)
```
Logo:        love•Me  (with breathing dot animation)
Body:        Send a message to get started.
Sub:         Connected to your Mac.
             (or: "Not connected." if daemon is down)
```

### Daemon Disconnected
```
Icon:        ○ (hollow dot, gray)
Headline:    Not connected
Body:        Make sure the love.Me daemon is running on your Mac.
CTA:         Try again
Secondary:   Connection settings
```

### No Tool Servers Configured
```
Headline:    No tools configured
Body:        I can chat, but I can't do anything on your machine yet.
             Add MCP servers to give me access to tools.
Helper:      Edit ~/.love-me/mcp.json to add tool servers.
```

---

## 3. Chat UI Microcopy

### Input Bar
```
Placeholder:        Message love.Me...
Placeholder (busy): Working on your last request...
```

### Streaming States
```
Typing indicator:   (animated dots — no text label)
Streaming label:    (none — the streaming text IS the indicator)
Stop button:        Stop
```

### Thinking Panel
```
Collapsed (streaming):   Thinking...          ▼
Collapsed (done):        Thought for 3s       ▼
Expanded header:         Thinking             ▲
```

No additional labels inside the expanded panel — the thinking text speaks for itself.

### Tool Cards

**Running:**
```
⚙️  read_file                    ⟳
    filesystem
```

**Success:**
```
✓  read_file                  0.3s
   filesystem
```

**Expanded success:**
```
✓  read_file                  0.3s
   filesystem
   ─────────────────────────────
   Input   {"path": "/src/app.ts"}
   Result  128 lines read
```

**Error:**
```
✗  run_command                Failed
   shell
```

**Expanded error:**
```
✗  run_command                Failed
   shell
   ─────────────────────────────
   Input   {"command": "npm test"}
   Error   Exit code 1: Test suite failed
```

### Timestamps
```
Just now
2m ago
1h ago
Yesterday, 11:42 PM
Feb 24, 3:15 PM
```
Never show seconds. Use relative for <24h, absolute after.

### Message Actions (Long Press)
```
Copy
Retry
Delete
```

---

## 4. Error Messages

### Connection Lost
```
Inline banner:   Connection lost. Reconnecting...
After 3 fails:   Can't reach your Mac. Check that the daemon is running.
                  [Try again]  [Settings]
```

### Reconnecting
```
Status dot:      ● (pulsing amber)
Nav subtitle:    Reconnecting...
```

### API Key Missing
```
Inline banner:   No API key found.
Body:            Set ANTHROPIC_API_KEY on your Mac and restart the daemon.
```

### Tool Execution Failed
```
(Shown in tool card, expanded)
Error: [actual error message from MCP server]
```
No wrapping, no sugar-coating. Show the real error. The user is technical.

### Message Send Failed
```
Below message bubble:  Not sent. Tap to retry.
```
Message bubble shows at reduced opacity (60%) with a small red indicator.

### Rate Limited
```
Inline:   Rate limited. Will retry in 30s.
```

### Daemon Crashed
```
Banner:    Daemon connection closed unexpectedly.
Body:      Restart the daemon on your Mac to continue.
           [Connection settings]
```

---

## 5. Settings Screen

### Navigation
```
Title:   Settings
```

### Connection Section
```
Section header:    CONNECTION
Host label:        Mac address
Host placeholder:  192.168.1.x or hostname
Host helper:       Your Mac's local IP address. Find it in System Settings → Wi-Fi.

Port label:        Port
Port placeholder:  9200
Port helper:       Default is 9200. Change only if you customized the daemon.

Test button:       Test connection
Test (testing):    Testing...            ⟳
Test (success):    Connected             ✓
Test (failed):     Can't connect. Check the address and make sure the daemon is running.
```

### Model Section
```
Section header:    MODEL
Model label:       Claude model
Model helper:      The AI model the daemon uses. Smarter models are slower.
```

### About Section
```
Section header:    ABOUT
Version:           love.Me v1.0.0
Daemon version:    Daemon v1.0.0  (or "Not connected")
```

### Danger Zone
```
Section header:    DATA
Delete all:        Delete all conversations
Confirmation:      This will delete all conversations on this device and your Mac. This can't be undone.
                   [Delete everything]  [Cancel]
```

---

## 6. Conversation List

### Header
```
Title:          love.Me
New button:     + (icon only, aria-label: "New conversation")
```

### List Item
```
Title:          [Auto-generated from first message, truncated]
Subtitle:       [Relative timestamp]
```

### Delete Confirmation
```
Title:          Delete this conversation?
Body:           This will remove it from this device and your Mac.
Destructive:    Delete
Cancel:         Cancel
```

### Search (if added later)
```
Placeholder:    Search conversations...
Empty result:   No matches found.
```

---

## 7. Daemon Menu Bar (macOS)

### Menu Items
```
Status:          ● Connected (1 device)
                 ○ Idle — no devices connected
                 ○ Stopped

Actions:         Show Logs
                 Restart Daemon
                 ─────────────
                 Start at Login    ✓
                 ─────────────
                 Quit love.Me
```

### Notifications (macOS)
```
Client connected:     love.Me: Device connected
Client disconnected:  love.Me: Device disconnected
Error:                love.Me: Daemon error — check logs
```

---

## 8. Accessibility Labels

```
Send button:              "Send message"
Connection dot:           "Connected to Mac" / "Disconnected from Mac"
Thinking panel:           "AI thinking, collapsed. Double tap to expand."
Tool card (running):      "[tool name] running on [server name]"
Tool card (done):         "[tool name] completed in [duration]"
Tool card (error):        "[tool name] failed on [server name]"
New conversation:         "Start new conversation"
Settings:                 "Settings"
Conversation item:        "[title], [timestamp]"
```

---

## 9. Push Notifications (Future)

```
Task complete:    love.Me: Done. [first 50 chars of response]
Error:            love.Me: Ran into an issue. Open to see details.
```

Never use "Hey!" or "Heads up!" in notifications. State what happened.

---

## Voice Checklist

Before shipping any copy, verify:

- [ ] First person? ("I" not "we" or "the system")
- [ ] Under 15 words for inline text?
- [ ] No exclamation marks? (max 1 per screen, only in success states)
- [ ] No "oops," "uh oh," or "whoops"?
- [ ] No emoji in error states?
- [ ] Shows the real error, not a generic message?
- [ ] One clear action per empty state?
- [ ] Calm, not apologetic?
