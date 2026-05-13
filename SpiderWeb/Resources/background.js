const APPLICATION_ID = "com.galewilliams.Savannah";
const PROTOCOL_VERSION = "0.1.0";
let nativePort = null;

async function collectTabs(reason) {
    const tabs = await browser.tabs.query({});

    return {
        kind: "savannah.tabSnapshot",
        protocolVersion: PROTOCOL_VERSION,
        reason,
        capturedAt: new Date().toISOString(),
        tabs: tabs.map((tab) => ({
            id: tab.id,
            windowId: tab.windowId,
            index: tab.index,
            active: tab.active,
            audible: tab.audible,
            discarded: tab.discarded,
            favIconUrl: tab.favIconUrl,
            incognito: tab.incognito,
            pinned: tab.pinned,
            status: tab.status,
            title: tab.title,
            url: tab.url
        }))
    };
}

async function publishTabs(reason) {
    try {
        const snapshot = await collectTabs(reason);
        const response = await browser.runtime.sendNativeMessage(APPLICATION_ID, snapshot);
        console.log("SpiderWeb published tab snapshot:", response);
        return response;
    } catch (error) {
        console.error("SpiderWeb could not publish tab snapshot:", error);
        return {
            ok: false,
            message: String(error)
        };
    }
}

async function createTab(request) {
    const tabRequest = {
        active: request.active !== false
    };

    if (typeof request.url === "string" && request.url.length > 0) {
        tabRequest.url = request.url;
    }

    await browser.tabs.create(tabRequest);
    return publishTabs("create-tab");
}

function handleNativePortMessage(message) {
    console.log("SpiderWeb received app message:", message);
    const command = message?.kind
        ? message
        : message?.userInfo?.kind
            ? message.userInfo
            : message?.message?.kind
                ? message.message
                : null;

    if (command?.kind === "savannah.createTab") {
        createTab(command).catch((error) => {
            console.error("SpiderWeb could not create requested tab:", error);
        });
    }
}

function connectNativePort() {
    try {
        nativePort = browser.runtime.connectNative(APPLICATION_ID);
        nativePort.onMessage.addListener(handleNativePortMessage);
        nativePort.onDisconnect.addListener(() => {
            console.warn("SpiderWeb native app port disconnected.");
            nativePort = null;
        });
    } catch (error) {
        console.error("SpiderWeb could not connect native app port:", error);
        nativePort = null;
    }
}

function schedulePublish(reason) {
    setTimeout(() => {
        publishTabs(reason);
    }, 0);
}

browser.runtime.onMessage.addListener((request) => {
    console.log("Received request: ", request);

    if (request.greeting === "hello") {
        return Promise.resolve({ farewell: "goodbye" });
    }

    if (request.kind === "savannah.snapshotTabs") {
        return publishTabs("runtime-message");
    }

    return undefined;
});

browser.tabs.onActivated.addListener(() => schedulePublish("tab-activated"));
browser.tabs.onCreated.addListener(() => schedulePublish("tab-created"));
browser.tabs.onRemoved.addListener(() => schedulePublish("tab-removed"));
browser.tabs.onUpdated.addListener(() => schedulePublish("tab-updated"));

connectNativePort();
schedulePublish("background-started");
