#!/usr/bin/env node
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { connect } from "node:net";
import { inspectCodexInstallSurfaces } from "./check-codex-install-surfaces.mjs";

const BACKEND_ID = "savannah";
const BACKEND_KIND = "chrome-compatible-proof";
const PROTOCOL_VERSION = "0.1.0";
const DEFAULT_RUNTIME_DIRECTORY = join(
  process.env.HOME ?? "",
  "Library",
  "Containers",
  "com.galewilliams.Savannah",
  "Data",
  "tmp",
  "savannah-codex"
);
const DEFAULT_SOCKET_PATH = join(DEFAULT_RUNTIME_DIRECTORY, "codex.sock");
const DEFAULT_TOKEN_PATH = join(DEFAULT_RUNTIME_DIRECTORY, "codex-token");

const capabilitySources = {
  ping: "plugin",
  getInfo: "plugin",
  getTabs: "unproven",
  getUserTabs: "unproven",
  getUserHistory: "unsupported",
  claimUserTab: "unproven",
  createTab: "web-extension",
  navigateTabUrl: "web-extension",
  navigate_tab_url: "web-extension",
  getTabInfo: "web-extension",
  reloadTab: "web-extension",
  navigate_tab_reload: "web-extension",
  closeTab: "web-extension",
  close_tab: "web-extension",
  getPageSnapshot: "web-extension",
  domCuaAction: "web-extension",
  dom_cua_get_visible_dom: "web-extension",
  dom_cua_click: "web-extension",
  dom_cua_type: "web-extension",
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
    socketPath: options.socketPath ?? process.env.SAVANNAH_SOCKET_PATH ?? DEFAULT_SOCKET_PATH,
    tokenPath: options.tokenPath ?? process.env.SAVANNAH_TOKEN_PATH ?? DEFAULT_TOKEN_PATH,
    requireApp: options.requireApp ?? process.env.SAVANNAH_REQUIRE_APP === "1",
    transport: options.transport ?? null,
    transportFailed: false,
    transportFailure: null
  };

  async function requestApp(method, params) {
    const transport = await resolveTransport(state);
    return transport.request(method, params);
  }

  async function appOrFallback(method, params, fallback) {
    try {
      return await requestApp(method, params);
    } catch (error) {
      state.transportFailed = true;
      state.transportFailure = error instanceof Error ? error.message : String(error);
      if (state.requireApp) {
        throw error;
      }
      return fallback();
    }
  }

  return {
    async ping() {
      return appOrFallback("ping", {}, () => ({
        ok: true,
        result: "pong",
        backendId: BACKEND_ID,
        backendKind: BACKEND_KIND,
        transport: fallbackTransportState(state)
      }));
    },

    async getInfo() {
      return appOrFallback("getInfo", {}, () => ({
        backendId: BACKEND_ID,
        backendKind: BACKEND_KIND,
        protocolVersion: PROTOCOL_VERSION,
        connection: {
          socketPath: state.socketPath,
          tokenPath: state.tokenPath,
          appConnection: state.transportFailed ? "failed" : "not-connected",
          failure: state.transportFailure
        },
        transport: fallbackTransportState(state),
        extensions: {
          spiderWeb: "unproven",
          safariTourGuide: "unproven"
        },
        capabilitySources
      }));
    },

    async getTabs() {
      return appOrFallback("getTabs", {}, () => ({
        tabs: [],
        inventory: "empty",
        capabilitySource: "unproven",
        transport: fallbackTransportState(state),
        message: "Savannah has not connected to the running app, SpiderWeb, SafariTourGuide, or native automation yet."
      }));
    },

    async getUserTabs() {
      return appOrFallback("getUserTabs", {}, () => this.getTabs());
    },

    async getUserHistory() {
      return unsupported("getUserHistory", "Safari history access is not implemented and no supported source has been proven.");
    },

    async claimUserTab(tab) {
      return unsupported("claimUserTab", "Savannah cannot claim Safari tabs until tab inventory is proven.", { tab });
    },

    async createTab(request) {
      return appOrFallback("createTab", request ?? {}, () => unsupported(
        "createTab",
        "Savannah cannot create Safari tabs until the running app and SpiderWeb extension are available.",
        { request }
      ));
    },

    async navigateTabUrl(request) {
      return appOrFallback("navigateTabUrl", normalizeNavigateTabRequest(request), () => unsupported(
        "navigateTabUrl",
        "Savannah cannot navigate Safari tabs until the running app and SpiderWeb extension are available.",
        { request }
      ));
    },

    async navigate_tab_url(request) {
      return this.navigateTabUrl(request);
    },

    async getTabInfo(request) {
      return appOrFallback("getTabInfo", normalizeTabRequest(request), () => unsupported(
        "getTabInfo",
        "Savannah cannot read Safari tab information until the running app and SpiderWeb extension are available.",
        { request }
      ));
    },

    async reloadTab(request) {
      return appOrFallback("reloadTab", normalizeTabRequest(request), () => unsupported(
        "reloadTab",
        "Savannah cannot reload Safari tabs until the running app and SpiderWeb extension are available.",
        { request }
      ));
    },

    async navigate_tab_reload(request) {
      return this.reloadTab(request);
    },

    async closeTab(request) {
      return appOrFallback("closeTab", normalizeTabRequest(request), () => unsupported(
        "closeTab",
        "Savannah cannot close Safari tabs until the running app and SpiderWeb extension are available.",
        { request }
      ));
    },

    async close_tab(request) {
      return this.closeTab(request);
    },

    async getPageSnapshot(request) {
      return appOrFallback("getPageSnapshot", normalizeTabRequest(request), () => unsupported(
        "getPageSnapshot",
        "Savannah cannot read Safari page snapshots until the running app and SpiderWeb content script are available.",
        { request }
      ));
    },

    async domCuaAction(request) {
      return appOrFallback("domCuaAction", normalizeDOMCuaActionRequest(request), () => unsupported(
        "domCuaAction",
        "Savannah cannot run DOM CUA actions until the running app and SpiderWeb content script are available.",
        { request }
      ));
    },

    async finalizeTabs() {
      return appOrFallback("finalizeTabs", {}, () => ({ ok: true, backendId: BACKEND_ID }));
    },

    async nameSession(name) {
      state.sessionName = name;
      return appOrFallback("nameSession", { name }, () => ({ ok: true, sessionName: state.sessionName }));
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
    },

    close() {
      state.transport?.close();
      state.transport = null;
    }
  };
}

export async function setupSavannahRuntime({ globals = globalThis, client = createSavannahClient() } = {}) {
  const browser = createBrowserFacade(client);
  globals.savannah = {
    browsers: {
      async get(id = "safari") {
        if (id !== "safari" && id !== BACKEND_ID) {
          throw new Error(`Savannah cannot select browser "${id}". Use "safari" or "${BACKEND_ID}".`);
        }
        return browser;
      },
      async list() {
        const info = await client.getInfo();
        return [{
          id: BACKEND_ID,
          name: "Savannah Safari",
          type: "safari",
          capabilitySources: info.capabilitySources
        }];
      }
    }
  };

  return globals.savannah;
}

function createBrowserFacade(client) {
  return {
    browserId: "safari",

    async nameSession(name) {
      return client.nameSession(name);
    },

    user: {
      async openTabs() {
        const result = await client.getUserTabs();
        return result.tabs ?? [];
      },

      async claimTab(tab) {
        return client.claimUserTab(tab);
      },

      async history(options = {}) {
        return client.getUserHistory(options);
      }
    },

    tabs: {
      async finalize(options = {}) {
        return client.finalizeTabs(options);
      },

      async get(id) {
        const result = await client.getTabInfo({ tabId: id });
        return createTabFacade(client, result.tab ?? result.id ?? id);
      },

      async list() {
        const result = await client.getTabs();
        return result.tabs ?? [];
      },

      async new() {
        const result = await client.createTab({ active: true });
        return createTabFacade(client, result.tab ?? result.id);
      },

      async selected() {
        const result = await client.getTabs();
        const tab = result.tabs?.find((item) => item.active) ?? result.tabs?.[0];
        return tab ? createTabFacade(client, tab) : undefined;
      }
    }
  };
}

function createTabFacade(client, tabOrId) {
  const id = normalizeTabId(tabOrId);

  return {
    id,

    async goto(url, options = {}) {
      await client.navigateTabUrl({ tabId: id, url, ...options });
    },

    async info() {
      const result = await client.getTabInfo({ tabId: id });
      return result.tab;
    },

    async url() {
      const tab = await findTabInfo(client, id);
      return tab?.url;
    },

    async title() {
      const tab = await findTabInfo(client, id);
      return tab?.title;
    },

    async reload() {
      await client.reloadTab({ tabId: id });
    },

    async close() {
      await client.closeTab({ tabId: id });
    },

    async pageSnapshot(options = {}) {
      const result = await client.getPageSnapshot({ tabId: id, ...options });
      return result.pageSnapshot;
    },

    dom_cua: {
      async get_visible_dom(options = {}) {
        const result = await client.getPageSnapshot({ tabId: id, ...options });
        return result.pageSnapshot;
      },

      async click(target, options = {}) {
        return client.domCuaAction({
          tabId: id,
          action: "click",
          ...normalizeDOMCuaTarget(target),
          ...options
        });
      },

      async type(target, text, options = {}) {
        return client.domCuaAction({
          tabId: id,
          action: "type",
          text,
          ...normalizeDOMCuaTarget(target),
          ...options
        });
      },

      async fill(target, text, options = {}) {
        return client.domCuaAction({
          tabId: id,
          action: "fill",
          text,
          ...normalizeDOMCuaTarget(target),
          ...options
        });
      }
    }
  };
}

async function findTabInfo(client, tabId) {
  const result = await client.getTabs();
  return result.tabs?.find((tab) => String(tab.id) === String(tabId));
}

function normalizeTabId(tabOrId) {
  if (tabOrId && typeof tabOrId === "object" && "id" in tabOrId) {
    return String(tabOrId.id);
  }

  if (tabOrId == null || String(tabOrId).length === 0) {
    throw new Error("Savannah could not create a tab facade because the tab id was missing.");
  }

  return String(tabOrId);
}

function normalizeNavigateTabRequest(request = {}) {
  return normalizeTabRequest(request, { requireURL: true });
}

function normalizeDOMCuaActionRequest(request = {}) {
  const normalized = normalizeTabRequest(request);
  if (typeof normalized.action !== "string" || normalized.action.length === 0) {
    throw new Error("Savannah cannot run a DOM CUA action because action was missing.");
  }

  if (!normalized.nodeId && !normalized.node_id && !normalized.selector) {
    throw new Error("Savannah cannot run a DOM CUA action because nodeId or selector was missing.");
  }

  return normalized;
}

function normalizeDOMCuaTarget(target) {
  if (typeof target === "string") {
    return target.startsWith("snapshot-")
      ? { nodeId: target }
      : { selector: target };
  }

  if (target && typeof target === "object") {
    return {
      nodeId: target.nodeId ?? target.node_id,
      selector: target.selector
    };
  }

  throw new Error("Savannah cannot target a DOM CUA action because the target was empty.");
}

function normalizeTabRequest(request = {}, options = {}) {
  if (request == null || typeof request !== "object") {
    request = { tabId: request };
  }

  const tabId = request.tabId ?? request.tab_id ?? request.id;
  if (tabId == null || String(tabId).length === 0) {
    throw new Error("Savannah cannot run the Safari tab command because tabId was missing.");
  }

  if (options.requireURL === true && (typeof request.url !== "string" || request.url.length === 0)) {
    throw new Error("Savannah cannot navigate a Safari tab because url was missing.");
  }

  return {
    ...request,
    tabId: String(tabId)
  };
}

async function resolveTransport(state) {
  if (state.transport) {
    return state.transport;
  }

  if (!existsSync(state.socketPath)) {
    throw new Error(`Savannah app socket is not available at ${state.socketPath}. Launch Savannah and retry.`);
  }

  const token = await readFile(state.tokenPath, "utf8")
    .then((value) => value.trim())
    .catch((error) => {
      throw new Error(`Savannah pairing token could not be read from ${state.tokenPath}: ${error.message}`);
    });

  state.transport = await SavannahJSONRPCTransport.connect({
    socketPath: state.socketPath,
    token
  });
  return state.transport;
}

function fallbackTransportState(state) {
  return {
    kind: "plugin-local-fallback",
    socketPath: state.socketPath,
    tokenPath: state.tokenPath,
    connected: false,
    failure: state.transportFailure
  };
}

class SavannahJSONRPCTransport {
  static async connect({ socketPath, token }) {
    const socket = connect(socketPath);
    const transport = new SavannahJSONRPCTransport(socket);
    await transport.openPromise;
    await transport.request("hello", {
      protocolVersion: PROTOCOL_VERSION,
      client: "savannah-codex-plugin",
      token
    });
    return transport;
  }

  constructor(socket) {
    this.socket = socket;
    this.nextId = 1;
    this.pending = new Map();
    this.buffer = Buffer.alloc(0);

    this.openPromise = new Promise((resolve, reject) => {
      socket.once("connect", resolve);
      socket.once("error", reject);
    });

    socket.on("data", (chunk) => this.receive(chunk));
    socket.on("error", (error) => this.rejectAll(error));
    socket.on("close", () => this.rejectAll(new Error("Savannah app socket closed.")));
  }

  request(method, params = {}) {
    const id = `req_${this.nextId++}`;
    const payload = Buffer.from(JSON.stringify({
      jsonrpc: "2.0",
      id,
      method,
      params
    }));
    const frame = Buffer.alloc(4 + payload.length);
    frame.writeUInt32BE(payload.length, 0);
    payload.copy(frame, 4);

    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.write(frame, (error) => {
        if (!error) {
          return;
        }
        this.pending.delete(id);
        reject(error);
      });
    });
  }

  receive(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);

    while (this.buffer.length >= 4) {
      const length = this.buffer.readUInt32BE(0);
      if (this.buffer.length < 4 + length) {
        return;
      }

      const payload = this.buffer.subarray(4, 4 + length);
      this.buffer = this.buffer.subarray(4 + length);
      this.handleMessage(JSON.parse(payload.toString("utf8")));
    }
  }

  handleMessage(message) {
    if (message.id == null) {
      return;
    }

    const pending = this.pending.get(message.id);
    if (!pending) {
      return;
    }
    this.pending.delete(message.id);

    if (message.error) {
      const error = new Error(message.error.message);
      error.code = message.error.code;
      error.data = message.error.data;
      pending.reject(error);
      return;
    }

    pending.resolve(message.result);
  }

  rejectAll(error) {
    for (const pending of this.pending.values()) {
      pending.reject(error);
    }
    this.pending.clear();
  }

  close() {
    this.socket.end();
    this.socket.destroy();
  }
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

  try {
    const result = await client[command](argument);
    console.log(JSON.stringify(result, null, 2));
  } finally {
    client.close();
  }
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
