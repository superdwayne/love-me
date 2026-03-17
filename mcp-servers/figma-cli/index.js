#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir } from "node:fs/promises";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const execFileAsync = promisify(execFile);

// ── Paths ───────────────────────────────────────────────────────────────────

const CLI_BIN = join(homedir(), ".local/bin/figma-cli");
const EXPORTS_DIR = join(homedir(), ".solace/figma-exports");

await mkdir(EXPORTS_DIR, { recursive: true });

// ── Helpers ─────────────────────────────────────────────────────────────────

async function runCLI(args, { timeout = 30000 } = {}) {
  try {
    const { stdout, stderr } = await execFileAsync(CLI_BIN, args, {
      timeout,
      env: { ...process.env, PATH: `${join(homedir(), ".local/bin")}:${process.env.PATH}` },
    });
    return stdout.trim() || stderr.trim();
  } catch (err) {
    if (err.stdout) return err.stdout.trim();
    throw new Error(err.stderr?.trim() || err.message);
  }
}

async function runREPL(commands, { timeout = 30000 } = {}) {
  const input = commands.join("\n") + "\nexit\n";
  try {
    const { stdout } = await execFileAsync(CLI_BIN, [], {
      timeout,
      input,
      env: { ...process.env, PATH: `${join(homedir(), ".local/bin")}:${process.env.PATH}` },
    });
    return stdout.trim();
  } catch (err) {
    if (err.stdout) return err.stdout.trim();
    throw new Error(err.stderr?.trim() || err.message);
  }
}

// ── MCP Server ──────────────────────────────────────────────────────────────

const server = new McpServer({
  name: "figma-cli",
  version: "1.0.0",
});

// PRIMARY: Execute a sequence of Figma CLI commands
server.tool(
  "figma_cli_run",
  "PRIMARY TOOL — Execute Figma CLI commands to inspect files, export assets, manage variables, styles, and components. Use this for any Figma operation via the CLI.",
  {
    commands: z.array(z.string()).describe("Array of figma-cli REPL commands. Examples: 'file info <file_key>', 'file pages <file_key>', 'export png <file_key> -n \"Button\" -s 2 -o /path/', 'component list <file_key>', 'variable list <file_key>', 'style list <file_key>'"),
  },
  async ({ commands }) => {
    try {
      const result = await runREPL(commands, { timeout: 60000 });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Figma CLI failed: ${err.message}` }], isError: true };
    }
  }
);

// File operations
server.tool(
  "figma_file_info",
  "Get information about a Figma file — pages, nodes, structure.",
  {
    file_key: z.string().describe("Figma file key (from the URL)"),
    action: z.enum(["info", "pages", "nodes", "search"]).optional().default("info").describe("Action: info, pages, nodes, search"),
    query: z.string().optional().describe("Search query (for action=search)"),
    page: z.string().optional().describe("Page name to inspect (for action=nodes)"),
  },
  async ({ file_key, action, query, page }) => {
    try {
      const args = ["file", action, file_key];
      if (query) args.push("-q", query);
      if (page) args.push("-p", page);
      const result = await runCLI(args);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

// Export assets
server.tool(
  "figma_export",
  "Export nodes from a Figma file as images (PNG, SVG, PDF, JPG).",
  {
    file_key: z.string().describe("Figma file key"),
    format: z.enum(["png", "svg", "pdf", "jpg"]).optional().default("png").describe("Export format"),
    node_name: z.string().optional().describe("Node name to export (searches by name)"),
    node_id: z.string().optional().describe("Node ID to export directly"),
    scale: z.number().optional().default(2).describe("Export scale (1-4)"),
    output_dir: z.string().optional().describe("Output directory (default: ~/.solace/figma-exports/)"),
  },
  async ({ file_key, format, node_name, node_id, scale, output_dir }) => {
    try {
      const outDir = output_dir || EXPORTS_DIR;
      const args = ["export", format, file_key, "-s", String(scale), "-o", outDir];
      if (node_name) args.push("-n", node_name);
      if (node_id) args.push("--id", node_id);
      const result = await runCLI(args, { timeout: 60000 });
      return { content: [{ type: "text", text: `Export complete.\nOutput: ${outDir}\n\n${result}` }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Export failed: ${err.message}` }], isError: true };
    }
  }
);

// Components
server.tool(
  "figma_components",
  "List or inspect components and component sets in a Figma file.",
  {
    file_key: z.string().describe("Figma file key"),
    action: z.enum(["list", "search"]).optional().default("list").describe("Action"),
    query: z.string().optional().describe("Search query for components"),
  },
  async ({ file_key, action, query }) => {
    try {
      const args = ["component", action, file_key];
      if (query) args.push("-q", query);
      const result = await runCLI(args);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

// Variables
server.tool(
  "figma_variables",
  "List or inspect variables and variable collections in a Figma file.",
  {
    file_key: z.string().describe("Figma file key"),
    action: z.enum(["list", "collections"]).optional().default("list").describe("Action"),
  },
  async ({ file_key, action }) => {
    try {
      const result = await runCLI(["variable", action, file_key]);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

// Styles
server.tool(
  "figma_styles",
  "List published styles in a Figma file.",
  {
    file_key: z.string().describe("Figma file key"),
  },
  async ({ file_key }) => {
    try {
      const result = await runCLI(["style", "list", file_key]);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

// Comments
server.tool(
  "figma_comments",
  "List or add comments on a Figma file.",
  {
    file_key: z.string().describe("Figma file key"),
    action: z.enum(["list", "add"]).optional().default("list").describe("Action"),
    message: z.string().optional().describe("Comment message (for action=add)"),
  },
  async ({ file_key, action, message }) => {
    try {
      const args = ["comment", action, file_key];
      if (message) args.push("-m", message);
      const result = await runCLI(args);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

// Projects
server.tool(
  "figma_projects",
  "Browse team projects and files.",
  {
    action: z.enum(["list", "files"]).optional().default("list").describe("Action: list projects or list files in a project"),
    project_id: z.string().optional().describe("Project ID (for listing files)"),
  },
  async ({ action, project_id }) => {
    try {
      const args = ["project", action];
      if (project_id) args.push(project_id);
      const result = await runCLI(args);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

// Help
server.tool(
  "figma_cli_help",
  "Get help on available figma-cli commands.",
  {
    command: z.string().optional().describe("Specific command to get help for"),
  },
  async ({ command }) => {
    try {
      const args = command ? [command, "--help"] : ["--help"];
      const result = await runCLI(args);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Help failed: ${err.message}` }], isError: true };
    }
  }
);

// ── Start ───────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
