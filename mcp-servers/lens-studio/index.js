#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { writeFile, mkdir } from "node:fs/promises";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const execFileAsync = promisify(execFile);

// ── Paths ───────────────────────────────────────────────────────────────────

const CLI_BIN = join(homedir(), ".local/bin/ls-cli");
const PROJECTS_DIR = join(homedir(), ".solace/lens-studio-projects");

await mkdir(PROJECTS_DIR, { recursive: true });

// ── Helpers ─────────────────────────────────────────────────────────────────

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

// ── MCP Server ──────────────────────────────────────────────────────────────

const server = new McpServer({
  name: "lens-studio-cli",
  version: "1.0.0",
});

// PRIMARY: Build a lens project via REPL commands
server.tool(
  "lens_studio_build",
  "PRIMARY TOOL — Build a Snap Lens Studio project by executing a sequence of ls-cli REPL commands. Creates AR lenses, face effects, world effects, and more. Commands run in order within a single session.",
  {
    project_name: z.string().describe("Project name"),
    commands: z.array(z.string()).describe("Array of ls-cli REPL commands. Examples: 'project new -n MyLens -t face-effects', 'scene add -n \"3D Object\"', 'material create -n GlowMat --type unlit', 'asset import texture /path/to/image.png', 'lens build -o output.lens'"),
  },
  async ({ project_name, commands }) => {
    try {
      const result = await runREPL(commands, { timeout: 60000 });
      return { content: [{ type: "text", text: `Lens project built.\n\n${result}` }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Build failed: ${err.message}` }], isError: true };
    }
  }
);

// Create a new project
server.tool(
  "lens_studio_project_new",
  "Create a new Lens Studio project from a template.",
  {
    name: z.string().describe("Project name"),
    template: z.string().optional().default("blank").describe("Template: blank, face-effects, world-effects, marker-tracking, body-tracking, hand-tracking, segmentation"),
    output_dir: z.string().optional().describe("Directory to create project in (default: ~/.solace/lens-studio-projects/)"),
  },
  async ({ name, template, output_dir }) => {
    try {
      const dir = output_dir || PROJECTS_DIR;
      const result = await runCLI(["project", "new", "-n", name, "-t", template, "-d", dir]);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

// Scene operations
server.tool(
  "lens_studio_scene",
  "Manage the scene graph — add, list, or remove objects in a Lens Studio project.",
  {
    action: z.enum(["add", "list", "remove"]).describe("Action to perform"),
    project_path: z.string().describe("Path to .lsproj file"),
    name: z.string().optional().describe("Object name (for add/remove)"),
    type: z.string().optional().describe("Object type for add (e.g., '3D Object', 'Camera', 'Light', 'Screen Image')"),
  },
  async ({ action, project_path, name, type }) => {
    try {
      const args = ["scene", action];
      if (name) args.push("-n", name);
      if (type) args.push("-t", type);
      const result = await runCLI(args, { projectPath: project_path });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Scene operation failed: ${err.message}` }], isError: true };
    }
  }
);

// Material operations
server.tool(
  "lens_studio_material",
  "Create or manage materials in a Lens Studio project.",
  {
    action: z.enum(["create", "list", "edit", "assign"]).describe("Action"),
    project_path: z.string().describe("Path to .lsproj file"),
    name: z.string().optional().describe("Material name"),
    type: z.string().optional().describe("Material type (e.g., unlit, pbr, face-paint)"),
    params: z.string().optional().describe("Additional parameters as key=value pairs"),
  },
  async ({ action, project_path, name, type, params }) => {
    try {
      const args = ["material", action];
      if (name) args.push("-n", name);
      if (type) args.push("--type", type);
      const result = await runCLI(args, { projectPath: project_path });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Material operation failed: ${err.message}` }], isError: true };
    }
  }
);

// Asset management
server.tool(
  "lens_studio_asset",
  "Import, list, or manage assets (textures, meshes, audio) in a Lens Studio project.",
  {
    action: z.enum(["import", "list", "remove"]).describe("Action"),
    project_path: z.string().describe("Path to .lsproj file"),
    asset_type: z.string().optional().describe("Asset type: texture, mesh, audio, animation"),
    file_path: z.string().optional().describe("File path to import"),
  },
  async ({ action, project_path, asset_type, file_path }) => {
    try {
      const args = ["asset", action];
      if (asset_type) args.push(asset_type);
      if (file_path) args.push(file_path);
      const result = await runCLI(args, { projectPath: project_path });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Asset operation failed: ${err.message}` }], isError: true };
    }
  }
);

// Lens build/preview
server.tool(
  "lens_studio_lens",
  "Build, export, or preview a lens.",
  {
    action: z.enum(["build", "preview", "export"]).describe("Action"),
    project_path: z.string().describe("Path to .lsproj file"),
    output: z.string().optional().describe("Output path for build/export"),
  },
  async ({ action, project_path, output }) => {
    try {
      const args = ["lens", action];
      if (output) args.push("-o", output);
      const result = await runCLI(args, { projectPath: project_path });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Lens operation failed: ${err.message}` }], isError: true };
    }
  }
);

// Templates
server.tool(
  "lens_studio_templates",
  "List available Lens Studio project templates.",
  {},
  async () => {
    try {
      const result = await runCLI(["template", "list"]);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

// Help
server.tool(
  "lens_studio_help",
  "Get help on available ls-cli commands.",
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

// List projects
server.tool(
  "lens_studio_list_projects",
  "List saved Lens Studio projects.",
  {},
  async () => {
    try {
      const files = readdirSync(PROJECTS_DIR, { withFileTypes: true })
        .filter(d => d.isDirectory())
        .map(d => d.name);
      if (files.length === 0) {
        return { content: [{ type: "text", text: "No projects found. Use lens_studio_project_new to create one." }] };
      }
      const list = files.map(f => `- ${f} → ${join(PROJECTS_DIR, f)}`).join("\n");
      return { content: [{ type: "text", text: `Lens Studio projects:\n\n${list}` }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed: ${err.message}` }], isError: true };
    }
  }
);

// ── Start ───────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
