const APPLICATION_ID = "com.galewilliams.Savannah";
const PROTOCOL_VERSION = "0.1.0";

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

schedulePublish("background-started");
