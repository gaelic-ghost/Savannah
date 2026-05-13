#!/usr/bin/env node
import { statSync } from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const home = os.homedir();

const knownSurfaces = {
  personalMarketplace: path.join(home, ".agents/plugins/marketplace.json"),
  personalPluginSourceRoot: path.join(home, ".codex/plugins"),
  pluginCacheRoot: path.join(home, ".codex/plugins/cache"),
  bundledChrome: path.join(home, ".codex/plugins/cache/openai-bundled/chrome"),
  bundledBrowser: path.join(home, ".codex/plugins/cache/openai-bundled/browser-use"),
  bundledComputerUse: path.join(home, ".codex/plugins/cache/openai-bundled/computer-use")
};

export async function inspectCodexInstallSurfaces(options = {}) {
  const repoRoot = options.repoRoot ?? findRepoRoot(process.cwd());
  const repoMarketplace = path.join(repoRoot, ".agents/plugins/marketplace.json");
  const repoPluginRoot = path.join(repoRoot, "plugins/savannah");

  return {
    repo: {
      root: repoRoot,
      marketplace: await describePath(repoMarketplace),
      savannahPluginRoot: await describePath(repoPluginRoot),
      savannahPluginManifest: await describePath(path.join(repoPluginRoot, ".codex-plugin/plugin.json"))
    },
    user: {
      personalMarketplace: await describePath(knownSurfaces.personalMarketplace),
      personalPluginSourceRoot: await describePath(knownSurfaces.personalPluginSourceRoot),
      pluginCacheRoot: await describePath(knownSurfaces.pluginCacheRoot)
    },
    bundled: {
      chrome: await describePluginVersions(knownSurfaces.bundledChrome),
      browserUse: await describePluginVersions(knownSurfaces.bundledBrowser),
      computerUse: await describePluginVersions(knownSurfaces.bundledComputerUse)
    },
    conclusion: [
      "Repo-local testing should use .agents/plugins/marketplace.json pointing at ./plugins/savannah.",
      "Normal installed plugins are loaded from ~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/ after Codex installs them.",
      "Chrome is currently installed as an OpenAI-bundled cache entry under ~/.codex/plugins/cache/openai-bundled/chrome/<version>/."
    ]
  };
}

async function describePluginVersions(root) {
  const rootInfo = await describePath(root);
  if (!rootInfo.exists || rootInfo.type !== "directory") {
    return { root: rootInfo, versions: [] };
  }

  const names = await fs.readdir(root);
  const versions = [];
  for (const name of names.sort()) {
    const versionRoot = path.join(root, name);
    const manifest = path.join(versionRoot, ".codex-plugin/plugin.json");
    const manifestInfo = await describePath(manifest);
    versions.push({
      version: name,
      root: await describePath(versionRoot),
      manifest: manifestInfo
    });
  }

  return { root: rootInfo, versions };
}

async function describePath(targetPath) {
  try {
    const stat = await fs.stat(targetPath);
    return {
      path: targetPath,
      exists: true,
      type: stat.isDirectory() ? "directory" : "file"
    };
  } catch (error) {
    if (error && error.code === "ENOENT") {
      return {
        path: targetPath,
        exists: false,
        type: null
      };
    }
    throw error;
  }
}

function findRepoRoot(start) {
  let current = path.resolve(start);
  while (current !== path.dirname(current)) {
    try {
      const stat = statSync(path.join(current, ".git"));
      if (stat.isDirectory() || stat.isFile()) {
        return current;
      }
    } catch {
      // Keep walking upward.
    }
    current = path.dirname(current);
  }
  return path.resolve(start);
}

async function main() {
  console.log(JSON.stringify(await inspectCodexInstallSurfaces(), null, 2));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(JSON.stringify({
      ok: false,
      error: {
        code: "install-surface-check-failed",
        message: error instanceof Error ? error.message : String(error)
      }
    }, null, 2));
    process.exitCode = 1;
  });
}
