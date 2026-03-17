#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { existsSync } from "node:fs";
import { writeFile, readFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir, homedir } from "node:os";

const execFileAsync = promisify(execFile);

// ── Paths ───────────────────────────────────────────────────────────────────

const CLI_BIN = join(homedir(), ".local/bin/cli-anything-blender");
const BLENDER_BIN = "/Applications/Blender.app/Contents/MacOS/Blender";
const PROJECTS_DIR = join(homedir(), ".solace/blender-projects");

// Ensure projects directory exists
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
    const { stdout } = await execFileAsync(CLI_BIN, ["repl"], {
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

async function runBlender(scriptPath, { timeout = 120000 } = {}) {
  try {
    const { stdout, stderr } = await execFileAsync(BLENDER_BIN, [
      "--background", "--python", scriptPath,
    ], { timeout });
    return stdout.trim() + (stderr ? `\n${stderr.trim()}` : "");
  } catch (err) {
    if (err.stdout) return err.stdout.trim();
    throw new Error(err.stderr?.trim() || err.message);
  }
}

// ── MCP Server ──────────────────────────────────────────────────────────────

const server = new McpServer({
  name: "blender",
  version: "1.0.0",
});

// Tool: Create a new scene
server.tool(
  "blender_scene_new",
  "UTILITY — Create a new CLI project file (headless). Prefer blender_create_live for creation requests.",
  {
    name: z.string().describe("Scene name"),
    output_path: z.string().optional().describe("Path to save the .blend-cli.json project file. Defaults to ~/.solace/blender-projects/<name>.blend-cli.json"),
    engine: z.enum(["CYCLES", "EEVEE", "WORKBENCH"]).optional().default("CYCLES").describe("Render engine"),
    resolution_x: z.number().optional().default(1920).describe("Horizontal resolution"),
    resolution_y: z.number().optional().default(1080).describe("Vertical resolution"),
    samples: z.number().optional().default(128).describe("Render samples"),
  },
  async ({ name, output_path, engine, resolution_x, resolution_y, samples }) => {
    try {
      const savePath = output_path || join(PROJECTS_DIR, `${name.replace(/\s+/g, "_")}.blend-cli.json`);
      const commands = [
        `scene new --name "${name}" --engine ${engine} -rx ${resolution_x} -ry ${resolution_y} --samples ${samples}`,
        `scene save ${savePath}`,
      ];
      const result = await runREPL(commands);
      return { content: [{ type: "text", text: `Scene created and saved to ${savePath}\n\n${result}` }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed to create scene: ${err.message}` }], isError: true };
    }
  }
);

// Tool: Build a scene from a list of REPL commands
server.tool(
  "blender_scene_build",
  "UTILITY — Build a scene via CLI REPL commands (headless, no GUI). Prefer blender_create_live for creation requests so the user sees the result live in Blender.",
  {
    project_name: z.string().describe("Project name (used for file naming)"),
    commands: z.array(z.string()).describe("Array of cli-anything-blender REPL commands to execute in order. Example commands: 'scene new --name MyScene', 'object add sphere -n Ball -l 0,0,0 -s 1,1,1', 'material create --name Red --color 0.8,0.1,0.1', 'material assign 0 0', 'camera add -n Cam -l 5,3,2', 'scene save /path/to/file.json'"),
  },
  async ({ project_name, commands }) => {
    try {
      const savePath = join(PROJECTS_DIR, `${project_name.replace(/\s+/g, "_")}.blend-cli.json`);
      // Ensure scene is saved at the end
      if (!commands.some(c => c.startsWith("scene save"))) {
        commands.push(`scene save ${savePath}`);
      }
      const result = await runREPL(commands, { timeout: 60000 });
      return { content: [{ type: "text", text: `Scene built and saved.\n\n${result}` }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed to build scene: ${err.message}` }], isError: true };
    }
  }
);

// Tool: Render a scene to an image
server.tool(
  "blender_render",
  "Render an existing Blender scene to a PNG image. Use only when the user asks for a rendered image output. For creating scenes, always use blender_create_live.",
  {
    project_path: z.string().optional().describe("Path to .blend-cli.json project file"),
    output_path: z.string().optional().describe("Output image path (default: /tmp/render_<timestamp>.png)"),
    script_path: z.string().optional().describe("Path to a custom Blender Python (.py) script to render instead of using a project file"),
  },
  async ({ project_path, output_path, script_path }) => {
    try {
      const outPath = output_path || `/tmp/blender_render_${Date.now()}.png`;

      if (script_path) {
        // Direct Blender render from Python script
        const result = await runBlender(script_path, { timeout: 120000 });
        return { content: [{ type: "text", text: `Render complete: ${outPath}\n\n${result}` }] };
      }

      if (!project_path) {
        return { content: [{ type: "text", text: "Either project_path or script_path is required" }], isError: true };
      }

      // Use cli-anything-blender to generate and execute render
      const result = await runCLI(["render", "execute", outPath, "--overwrite"], { projectPath: project_path, timeout: 120000 });

      // If the CLI generated a render script, run it with Blender
      const scriptMatch = result.match(/command: blender --background --python (.+)/);
      if (scriptMatch) {
        const blenderResult = await runBlender(scriptMatch[1].trim(), { timeout: 120000 });
        return { content: [{ type: "text", text: `Render complete: ${outPath}\n\n${blenderResult}` }] };
      }

      return { content: [{ type: "text", text: `Render initiated: ${outPath}\n\n${result}` }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Render failed: ${err.message}` }], isError: true };
    }
  }
);

// Tool: Generate a Blender Python script from a project
server.tool(
  "blender_generate_script",
  "UTILITY — Generate a .py script from a CLI project file. Rarely needed directly.",
  {
    project_path: z.string().describe("Path to .blend-cli.json project file"),
    output_path: z.string().optional().describe("Output .py script path (default: auto-generated)"),
  },
  async ({ project_path, output_path }) => {
    try {
      const outPath = output_path || `/tmp/blender_script_${Date.now()}.py`;
      const result = await runCLI(["render", "script", outPath], { projectPath: project_path });
      return { content: [{ type: "text", text: `Script generated: ${outPath}\n\n${result}` }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Script generation failed: ${err.message}` }], isError: true };
    }
  }
);

// Tool: Run a custom Blender Python script
server.tool(
  "blender_run_script",
  "INTERNAL/UTILITY — Run a Blender Python script headlessly in the background (no GUI). Only use this when explicitly asked to render to an image file or for batch processing. For normal creation requests, use blender_create_live instead.",
  {
    script_content: z.string().optional().describe("Python script content to execute. Will be written to a temp file."),
    script_path: z.string().optional().describe("Path to an existing .py script file to execute"),
    output_image_path: z.string().optional().describe("Expected output image path (for reference)"),
  },
  async ({ script_content, script_path, output_image_path }) => {
    try {
      let scriptFile = script_path;

      if (script_content && !script_path) {
        scriptFile = `/tmp/blender_custom_${Date.now()}.py`;
        await writeFile(scriptFile, script_content, "utf-8");
      }

      if (!scriptFile) {
        return { content: [{ type: "text", text: "Either script_content or script_path is required" }], isError: true };
      }

      const result = await runBlender(scriptFile, { timeout: 180000 });

      let text = `Script executed successfully.\n\n${result}`;
      if (output_image_path) {
        text += `\n\nOutput image: ${output_image_path}`;
      }

      return { content: [{ type: "text", text }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Script execution failed: ${err.message}` }], isError: true };
    }
  }
);

// Tool: Create scene LIVE in Blender GUI (user watches it being built)
server.tool(
  "blender_create_live",
  "PRIMARY TOOL — Always use this for ANY Blender creation request. Creates a 3D scene and opens it LIVE in the Blender GUI so the user watches it being built in the viewport. The script runs inside Blender with the full 3D viewport visible. DO NOT include bpy.ops.render.render() — the scene stays open for the user to explore and interact with. Always save a .blend file. This is the DEFAULT tool for creating, modeling, building, or generating anything in Blender.",
  {
    script_content: z.string().describe("Blender Python script that creates the scene. Must NOT call bpy.ops.render.render(). Should save a .blend file with bpy.ops.wm.save_as_mainfile(). The scene will be visible in Blender's viewport."),
    project_name: z.string().optional().default("scene").describe("Name for the project (used in file naming)"),
  },
  async ({ script_content, project_name }) => {
    try {
      const { spawn } = await import("node:child_process");

      // Strip any render calls so Blender stays open
      let cleaned = script_content
        .replace(/bpy\.ops\.render\.render\([^)]*\)/g, "# render removed — scene stays open for viewing")
        .replace(/print\(['"]Render complete.*?\)/g, "");

      // Ensure it saves a .blend file
      const blendPath = join(PROJECTS_DIR, `${project_name.replace(/\s+/g, "_")}.blend`);
      if (!cleaned.includes("save_as_mainfile")) {
        cleaned += `\n\n# Auto-save .blend file\nbpy.ops.wm.save_as_mainfile(filepath=r'${blendPath}')\nprint('Saved: ${blendPath}')\n`;
      }

      // Write script to temp file
      const scriptFile = `/tmp/blender_live_${Date.now()}.py`;
      await writeFile(scriptFile, cleaned, "utf-8");

      // Launch Blender WITH GUI (not --background)
      const child = spawn(BLENDER_BIN, ["--python", scriptFile], {
        detached: true,
        stdio: "ignore",
      });
      child.unref();

      return {
        content: [{
          type: "text",
          text: `Blender GUI launched — the scene is being built live in the viewport.\n\nProject saved to: ${blendPath}\nScript: ${scriptFile}\n\nYou can interact with the scene in Blender's viewport, rotate the camera, and explore the 3D model.`,
        }],
      };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed to create live scene: ${err.message}` }], isError: true };
    }
  }
);

// Tool: Open scene in Blender GUI
server.tool(
  "blender_open",
  "Open an existing .blend file or run a script in the Blender GUI for interactive viewing and editing.",
  {
    blend_file: z.string().optional().describe("Path to a .blend file to open"),
    script_path: z.string().optional().describe("Path to a .py script to run on launch (Blender opens with GUI after executing the script)"),
  },
  async ({ blend_file, script_path }) => {
    try {
      const { spawn } = await import("node:child_process");
      const args = [];

      if (blend_file) {
        args.push(blend_file);
      }
      if (script_path) {
        args.push("--python", script_path);
      }

      // Launch Blender with GUI (non-blocking, detached)
      const child = spawn(BLENDER_BIN, args, {
        detached: true,
        stdio: "ignore",
      });
      child.unref();

      let msg = "Blender GUI launched";
      if (blend_file) msg += ` with ${blend_file}`;
      if (script_path) msg += ` running ${script_path}`;

      return { content: [{ type: "text", text: msg }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed to open Blender: ${err.message}` }], isError: true };
    }
  }
);

// Tool: List available objects/commands
server.tool(
  "blender_help",
  "Get help and list available cli-anything-blender commands and subcommands",
  {
    command: z.string().optional().describe("Specific command to get help for (e.g., 'object', 'material', 'render')"),
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

// Tool: List projects
server.tool(
  "blender_list_projects",
  "List all saved Blender projects in the Solace projects directory",
  {},
  async () => {
    try {
      const { readdirSync } = await import("node:fs");
      const files = readdirSync(PROJECTS_DIR).filter(f => f.endsWith(".blend-cli.json"));
      if (files.length === 0) {
        return { content: [{ type: "text", text: "No Blender projects found. Use blender_scene_build to create one." }] };
      }
      const list = files.map(f => `- ${f} → ${join(PROJECTS_DIR, f)}`).join("\n");
      return { content: [{ type: "text", text: `Blender projects:\n\n${list}` }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed to list projects: ${err.message}` }], isError: true };
    }
  }
);

// ── Start ───────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
