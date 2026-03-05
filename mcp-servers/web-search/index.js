#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

// ── DuckDuckGo HTML search ──────────────────────────────────────────────────

async function duckduckgoSearch(query, numResults = 10, timeFilter) {
  const params = new URLSearchParams({ q: query, kl: "", kp: "-2" });
  if (timeFilter) {
    const map = { day: "d", week: "w", month: "m", year: "y" };
    if (map[timeFilter]) params.set("df", map[timeFilter]);
  }

  const url = `https://html.duckduckgo.com/html/?${params}`;
  const res = await fetch(url, {
    headers: { "User-Agent": USER_AGENT },
    redirect: "follow",
  });

  if (!res.ok) throw new Error(`DuckDuckGo returned ${res.status}`);

  const html = await res.text();
  const results = [];

  // Parse result blocks from DDG HTML
  const resultRegex =
    /<a[^>]+class="result__a"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>[\s\S]*?<a[^>]+class="result__snippet"[^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = resultRegex.exec(html)) !== null && results.length < numResults) {
    let href = match[1];
    // DDG wraps URLs in a redirect — extract the real URL
    const uddg = new URLSearchParams(new URL(href, "https://duckduckgo.com").search).get("uddg");
    if (uddg) href = uddg;

    const title = match[2].replace(/<[^>]+>/g, "").trim();
    const snippet = match[3].replace(/<[^>]+>/g, "").trim();

    if (title && href && !href.startsWith("/")) {
      results.push({ title, url: decodeURIComponent(href), snippet });
    }
  }

  // Fallback: try simpler pattern if the above found nothing
  if (results.length === 0) {
    const linkRegex = /<a[^>]+class="result__a"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi;
    while ((match = linkRegex.exec(html)) !== null && results.length < numResults) {
      let href = match[1];
      const uddg = new URLSearchParams(new URL(href, "https://duckduckgo.com").search).get("uddg");
      if (uddg) href = uddg;
      const title = match[2].replace(/<[^>]+>/g, "").trim();
      if (title && href && !href.startsWith("/")) {
        results.push({ title, url: decodeURIComponent(href), snippet: "" });
      }
    }
  }

  return results;
}

// ── Fetch & extract page text ───────────────────────────────────────────────

async function fetchPage(url, maxLength = 8000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);

  try {
    const res = await fetch(url, {
      headers: { "User-Agent": USER_AGENT, Accept: "text/html,application/xhtml+xml,*/*" },
      signal: controller.signal,
      redirect: "follow",
    });
    clearTimeout(timeout);

    if (!res.ok) throw new Error(`HTTP ${res.status} from ${url}`);

    const contentType = res.headers.get("content-type") || "";
    if (!contentType.includes("html") && !contentType.includes("text")) {
      return `[Non-text content: ${contentType}]`;
    }

    const html = await res.text();

    // Strip scripts, styles, and tags
    let text = html
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/<style[\s\S]*?<\/style>/gi, "")
      .replace(/<nav[\s\S]*?<\/nav>/gi, "")
      .replace(/<header[\s\S]*?<\/header>/gi, "")
      .replace(/<footer[\s\S]*?<\/footer>/gi, "")
      .replace(/<[^>]+>/g, " ")
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/\s+/g, " ")
      .trim();

    if (text.length > maxLength) {
      text = text.slice(0, maxLength) + "\n\n[Truncated — content exceeds limit]";
    }

    return text;
  } catch (err) {
    clearTimeout(timeout);
    throw err;
  }
}

// ── MCP Server ──────────────────────────────────────────────────────────────

const server = new McpServer({
  name: "web-search",
  version: "1.0.0",
});

server.tool(
  "web_search",
  "Search the web using DuckDuckGo and return results with titles, URLs, and snippets",
  {
    query: z.string().describe("The search query"),
    num_results: z.number().optional().default(10).describe("Number of results to return (default 10, max 20)"),
    time_filter: z.string().optional().describe("Filter results by time period: day, week, month, or year"),
  },
  async ({ query, num_results, time_filter }) => {
    try {
      const results = await duckduckgoSearch(query, Math.min(num_results || 10, 20), time_filter);

      if (results.length === 0) {
        return { content: [{ type: "text", text: `No results found for: "${query}"` }] };
      }

      const formatted = results
        .map((r, i) => `${i + 1}. **${r.title}**\n   ${r.url}\n   ${r.snippet}`)
        .join("\n\n");

      return {
        content: [
          {
            type: "text",
            text: `Found ${results.length} results for "${query}":\n\n${formatted}`,
          },
        ],
      };
    } catch (err) {
      return { content: [{ type: "text", text: `Search failed: ${err.message}` }], isError: true };
    }
  }
);

server.tool(
  "fetch_page",
  "Fetch a web page and extract its text content (HTML stripped)",
  {
    url: z.string().url().describe("The URL to fetch"),
    max_length: z
      .number()
      .optional()
      .default(8000)
      .describe("Maximum character length of extracted text (default 8000)"),
  },
  async ({ url, max_length }) => {
    try {
      const text = await fetchPage(url, max_length || 8000);
      return { content: [{ type: "text", text }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Failed to fetch ${url}: ${err.message}` }], isError: true };
    }
  }
);

// ── Start ───────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
