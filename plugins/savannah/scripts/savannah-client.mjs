#!/usr/bin/env node
import { inspectCodexInstallSurfaces } from "./check-codex-install-surfaces.mjs";

const BACKEND_ID = "savannah";
const BACKEND_KIND = "chrome-compatible-proof";

const capabilitySources = {
  ping: "plugin",
  getInfo: "plugin",
  getTabs: "unproven",
  getUserTabs: "unproven",
  getUserHistory: "unsupported",
  claimUserTab: "unproven",
  createTab: "unproven",
  finalizeTabs: "plugin",
  nameSession: "plugin",
  attach: "unproven",
  detach: "unproven",
  executeCdp: "unsupported",
  executeUnhandledCommand: "plugin",
  moveMouse: "unproven"
};

export function createSavannahClient(options = {}) {
  const state = {
    sessionName: null,
    endpoint: options.endpoint ?? process.env.SAVANNAH_ENDPOINT ?? null
  };

  return {
    async ping() {
      return {
        ok: true,
        result: "pong",
        backendId: BACKEND_ID,
        backendKind: BACKEND_KIND
      };
    },

    async getInfo() {
      return {
        backendId: BACKEND_ID,
        backendKind: BACKEND_KIND,
        protocolVersion: "0.1.0",
        connection: {
          appEndpointConfigured: Boolean(state.endpoint),
          appEndpoint: state.endpoint,
          appConnection: state.endpoint ? "unproven" : "not-configured"
        },
        extensions: {
          spiderWeb: "unproven",
          safariTourGuide: "unproven"
        },
        capabilitySources
      };
    },

    async getTabs() {
      return {
        tabs: [],
        inventory: "empty",
        capabilitySource: "unproven",
        message: "Savannah has not connected to SpiderWeb, SafariTourGuide, or native automation yet."
      };
    },

    async getUserTabs() {
      return this.getTabs();
    },

    async getUserHistory() {
      return unsupported("getUserHistory", "Safari history access is not implemented and no supported source has been proven.");
    },

    async claimUserTab(tab) {
      return unsupported("claimUserTab", "Savannah cannot claim Safari tabs until tab inventory is proven.", { tab });
    },

    async createTab(request) {
      return unsupported("createTab", "Savannah cannot create Safari tabs until the WebExtension or App Extension route is proven.", { request });
    },

    async finalizeTabs() {
      return { ok: true, backendId: BACKEND_ID };
    },

    async nameSession(name) {
      state.sessionName = name;
      return { ok: true, sessionName: state.sessionName };
    },

    async attach(target) {
      return unsupported("attach", "Savannah cannot attach to Safari pages until an observable target route is proven.", { target });
    },

    async detach(target) {
      return unsupported("detach", "Savannah has no attached Safari page session to detach yet.", { target });
    },

    async executeCdp(command) {
      return unsupported("executeCdp", "Safari does not expose a Chrome DevTools Protocol bridge through the current Savannah design.", { command });
    },

    async executeUnhandledCommand(command) {
      return unsupported("executeUnhandledCommand", "No Savannah command handler matched this request.", { command });
    },

    async moveMouse(request) {
      return unsupported("moveMouse", "Savannah has not proven page overlay messaging through a Safari extension yet.", { request });
    },

    async inspectInstallSurfaces() {
      return inspectCodexInstallSurfaces();
    }
  };
}

function unsupported(command, message, detail = {}) {
  return {
    ok: false,
    error: {
      code: "unsupported-command",
      command,
      message,
      capabilitySource: capabilitySources[command] ?? "unsupported",
      detail
    }
  };
}

async function main() {
  const command = process.argv[2] ?? "getInfo";
  const argument = process.argv[3] ? JSON.parse(process.argv[3]) : undefined;
  const client = createSavannahClient();

  if (typeof client[command] !== "function") {
    console.error(JSON.stringify(unsupported(command, `Unknown Savannah proof command: ${command}`), null, 2));
    process.exitCode = 2;
    return;
  }

  const result = await client[command](argument);
  console.log(JSON.stringify(result, null, 2));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(JSON.stringify({
      ok: false,
      error: {
        code: "savannah-client-failed",
        message: error instanceof Error ? error.message : String(error)
      }
    }, null, 2));
    process.exitCode = 1;
  });
}

