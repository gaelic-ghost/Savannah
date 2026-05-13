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
      return unsupported("createTab", "Savannah cannot create Safari tabs until the WebExtension or App Extension route is proven.", { request });
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
        return client.attach({ id });
      },

      async list() {
        const result = await client.getTabs();
        return result.tabs ?? [];
      },

      async new(request = {}) {
        return client.createTab(request);
      },

      async selected() {
        const result = await client.getTabs();
        return result.tabs?.[0];
      }
    }
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
