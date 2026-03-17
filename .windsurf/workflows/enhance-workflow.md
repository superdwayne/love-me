---
description: Analyze and enhance an existing workflow by detecting missing elements, asking clarifying questions, and rebuilding it
---

# Enhance Workflow

This workflow analyzes an existing `.windsurf/workflows/*.md` workflow file, detects missing or incomplete elements, asks targeted questions to fill the gaps, and then rebuilds/edits the workflow to be production-ready.

## Steps

### 1. Identify the Target Workflow

- Ask the user which workflow they want to enhance, or detect from context (e.g., the currently open file).
- If the user doesn't specify, list all files in `.windsurf/workflows/` and ask them to pick one.
- Read the full contents of the target workflow file.

### 2. Run the Quality Audit

Analyze the workflow against this **completeness checklist**. For each item, mark it as ✅ present, ⚠️ partial, or ❌ missing:

#### Frontmatter
- [ ] Has valid YAML frontmatter (`---` delimiters)
- [ ] Has a `description` field that clearly summarizes what the workflow does in one sentence

#### Structure & Clarity
- [ ] Has a top-level heading (`#`) with the workflow name
- [ ] Has a brief introduction paragraph explaining the workflow's purpose and when to use it
- [ ] Steps are numbered sequentially
- [ ] Each step has a clear, actionable title
- [ ] Steps are in a logical dependency order (no step references something defined later)

#### Step Completeness — For Each Step, Check:
- [ ] **What**: Clear description of what this step does
- [ ] **How**: Specific commands, tool calls, or actions to perform (not vague instructions)
- [ ] **Where**: File paths, directories, or targets are specified (not just "the file")
- [ ] **Input/Output**: What this step needs and what it produces
- [ ] **Error handling**: What to do if this step fails (fallback, retry, or abort)
- [ ] **Verification**: How to confirm this step succeeded before moving on

#### Automation Readiness
- [ ] Commands use absolute paths or well-defined variables (no ambiguous relative paths)
- [ ] Any `run_command` steps specify a `Cwd` (working directory)
- [ ] Steps that are safe to auto-run are annotated with `// turbo`
- [ ] Dangerous/destructive steps are clearly marked as requiring user approval
- [ ] Environment prerequisites are listed (required tools, API keys, running services)

#### Robustness
- [ ] Edge cases are addressed (empty input, missing files, network errors)
- [ ] Idempotency: running the workflow twice doesn't break anything
- [ ] Rollback: destructive steps mention how to undo if needed
- [ ] Conditional logic: handles branching scenarios (if X then do Y, otherwise Z)

#### Integration
- [ ] References correct project paths for this workspace (`/Users/dwayne/love-me/...`)
- [ ] Uses the project's established patterns (Swift actors, WebSocket protocol, MCP tool calls, etc.)
- [ ] Cross-references related PRDs, protocols, or docs where relevant

### 3. Present the Audit Report

Show the user a summary table like:

```
## Workflow Audit: <workflow-name>

| Category              | Status | Issues Found |
|-----------------------|--------|--------------|
| Frontmatter           | ✅/⚠️/❌ | ...        |
| Structure & Clarity   | ✅/⚠️/❌ | ...        |
| Step Completeness     | ✅/⚠️/❌ | ...        |
| Automation Readiness  | ✅/⚠️/❌ | ...        |
| Robustness            | ✅/⚠️/❌ | ...        |
| Integration           | ✅/⚠️/❌ | ...        |
```

List each specific issue found with a brief explanation of why it matters.

### 4. Ask Targeted Questions

For every ❌ missing or ⚠️ partial item, ask the user a **specific, answerable question** to gather the missing information. Group questions by category. Examples:

- "Step 3 says 'update the config' but doesn't specify which config file or what values. Which config file should be modified, and what keys/values need to change?"
- "There's no error handling if the build fails in Step 5. Should the workflow abort, retry, or skip to the next step?"
- "The workflow doesn't mention any prerequisites. Does it require any running services (e.g., the daemon on port 9200) or API keys?"
- "Steps 2 and 4 both modify the same file but don't mention ordering. Should Step 4 always run after Step 2, or can they be independent?"

Present questions as a numbered list so the user can answer by number or answer all at once.

### 5. Rebuild the Workflow

Using the user's answers, edit the workflow file with these enhancements:

- Fix all ❌ missing items by adding the required content
- Improve all ⚠️ partial items with more specific detail
- Preserve all ✅ existing content that was already good
- Maintain the user's original intent and voice — don't over-engineer or change the workflow's purpose
- Use the `edit` or `multi_edit` tool to make changes in-place (don't rewrite the whole file unless >50% needs changing)

### 6. Verify the Enhanced Workflow

After editing:

- Re-read the workflow file and confirm all checklist items now pass
- Show the user a before/after diff summary of what changed
- Ask: "Does this look right? Anything you'd like to adjust?"

### 7. Final Polish (Optional)

If the user is satisfied, offer these optional improvements:

- Add `// turbo` annotations to safe steps
- Add a "Prerequisites" section at the top
- Add a "Troubleshooting" section at the bottom for common failure modes
- Cross-link to related workflows or project docs

## Notes

- This workflow is **interactive** — it requires user input at Steps 1, 4, and 6 at minimum.
- Never delete user content without asking. Always preserve intent.
- If the workflow is already complete (all ✅), tell the user and offer minor polish suggestions instead of forcing changes.
- For brand-new workflows that are mostly empty, skip the audit and go straight to a guided creation flow: ask purpose, triggers, steps, and build from scratch.
