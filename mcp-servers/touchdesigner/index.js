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

const CLI_BIN = join(homedir(), ".local/bin/td-cli");
const PROJECTS_DIR = join(homedir(), ".solace/touchdesigner-projects");

await mkdir(PROJECTS_DIR, { recursive: true });

async function runCLI(args, { projectPath, timeout = 30000 } = {}) {
  const fullArgs = [];
  if (projectPath) fullArgs.push("--project", projectPath);
  fullArgs.push(...args);
  try {
    const { stdout, stderr } = await execFileAsync(CLI_BIN, fullArgs, {
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

const server = new McpServer({ name: "touchdesigner-cli", version: "1.0.0" });

server.tool(
  "td_build",
  "PRIMARY TOOL — Build a TouchDesigner project by executing a sequence of td-cli REPL commands. Creates networks, operators, connections, and renders. Commands run in order within a single session.",
  {
    project_name: z.string().describe("Project name"),
    commands: z.array(z.string()).describe("Array of td-cli REPL commands. Examples: 'project new -n MyVisuals', 'op add -t noise -n noise1', 'op add -t level -n level1', 'net connect noise1 level1', 'render -o output.png'"),
  },
  async ({ project_name, commands }) => {
    try {
      const result = await runREPL(commands, { timeout: 60000 });
      return { content: [{ type: "text", text: `TD project built.\n\n${result}` }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Build failed: ${err.message}` }], isError: true };
    }
  }
);

server.tool(
  "td_project",
  "Manage TouchDesigner projects — create, open, save, info.",
  {
    action: z.enum(["new", "open", "save", "info", "list"]).describe("Action"),
    name: z.string().optional().describe("Project name (for new)"),
    path: z.string().optional().describe("Project file path (for open/save)"),
  },
  async ({ action, name, path }) => {
    try {
      const args = ["project", action];
      if (name) args.push("-n", name);
      if (path) args.push(path);
      const result = await runCLI(args);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

server.tool(
  "td_op",
  "Manage operators — add, list, remove, edit, get info.",
  {
    action: z.enum(["add", "list", "remove", "info", "set"]).describe("Action"),
    project_path: z.string().optional().describe("Project file path"),
    type: z.string().optional().describe("Operator type (noise, level, transform, composite, etc.)"),
    name: z.string().optional().describe("Operator name"),
    params: z.string().optional().describe("Parameters as key=value pairs"),
  },
  async ({ action, project_path, type, name, params }) => {
    try {
      const args = ["op", action];
      if (type) args.push("-t", type);
      if (name) args.push("-n", name);
      if (params) args.push("--params", params);
      const result = await runCLI(args, { projectPath: project_path });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Op failed: ${err.message}` }], isError: true };
    }
  }
);

server.tool(
  "td_net",
  "Manage network connections between operators.",
  {
    action: z.enum(["connect", "disconnect", "list"]).describe("Action"),
    project_path: z.string().optional().describe("Project file path"),
    source: z.string().optional().describe("Source operator name"),
    target: z.string().optional().describe("Target operator name"),
  },
  async ({ action, project_path, source, target }) => {
    try {
      const args = ["net", action];
      if (source) args.push(source);
      if (target) args.push(target);
      const result = await runCLI(args, { projectPath: project_path });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Net failed: ${err.message}` }], isError: true };
    }
  }
);

server.tool(
  "td_render",
  "Render output from a TouchDesigner project.",
  {
    project_path: z.string().optional().describe("Project file path"),
    output: z.string().optional().describe("Output file path"),
    format: z.string().optional().describe("Output format (png, jpg, mov)"),
    frames: z.number().optional().describe("Number of frames to render"),
  },
  async ({ project_path, output, format, frames }) => {
    try {
      const args = ["render"];
      if (output) args.push("-o", output);
      if (format) args.push("-f", format);
      if (frames) args.push("--frames", String(frames));
      const result = await runCLI(args, { projectPath: project_path, timeout: 120000 });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Render failed: ${err.message}` }], isError: true };
    }
  }
);

server.tool(
  "td_export",
  "Export a TouchDesigner project in various formats.",
  {
    project_path: z.string().optional().describe("Project file path"),
    format: z.string().optional().describe("Export format"),
    output: z.string().optional().describe("Output path"),
  },
  async ({ project_path, format, output }) => {
    try {
      const args = ["export"];
      if (format) args.push("-f", format);
      if (output) args.push("-o", output);
      const result = await runCLI(args, { projectPath: project_path });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Export failed: ${err.message}` }], isError: true };
    }
  }
);

server.tool(
  "td_status",
  "Show TouchDesigner backend connection status.",
  {},
  async () => {
    try {
      const result = await runCLI(["status"]);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Status check failed: ${err.message}` }], isError: true };
    }
  }
);

server.tool(
  "td_help",
  "Get help on available td-cli commands.",
  { command: z.string().optional().describe("Specific command to get help for") },
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

const transport = new StdioServerTransport();
await server.connect(transport);
