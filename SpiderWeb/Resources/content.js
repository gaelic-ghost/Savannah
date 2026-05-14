const PROTOCOL_VERSION = "0.1.0";
const MAX_VISIBLE_TEXT_LENGTH = 20000;
const MAX_INTERACTIVE_ELEMENTS = 100;

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    console.log("SpiderWeb content script received request: ", request);

    if (request?.kind === "savannah.getPageSnapshot") {
        return Promise.resolve(collectPageSnapshot(request));
    }

    if (request?.kind === "savannah.domCuaAction") {
        return Promise.resolve(runDOMCuaAction(request));
    }

    return undefined;
});

function collectPageSnapshot(request) {
    return {
        kind: "savannah.pageSnapshot",
        protocolVersion: PROTOCOL_VERSION,
        capturedAt: new Date().toISOString(),
        url: window.location.href,
        title: document.title,
        readyState: document.readyState,
        visibilityState: document.visibilityState,
        viewport: {
            width: window.innerWidth,
            height: window.innerHeight,
            scrollX: window.scrollX,
            scrollY: window.scrollY,
            devicePixelRatio: window.devicePixelRatio
        },
        visibleText: truncateText(document.body?.innerText ?? "", request.maxTextLength ?? MAX_VISIBLE_TEXT_LENGTH),
        interactiveElements: collectInteractiveElements()
    };
}

function collectInteractiveElements() {
    const selector = [
        "a[href]",
        "button",
        "input",
        "textarea",
        "select",
        "[role='button']",
        "[role='link']",
        "[contenteditable='true']"
    ].join(",");

    return interactiveElementRecords()
        .map((record) => record.summary);
}

function interactiveElementRecords() {
    const selector = [
        "a[href]",
        "button",
        "input",
        "textarea",
        "select",
        "[role='button']",
        "[role='link']",
        "[contenteditable='true']"
    ].join(",");

    return Array.from(document.querySelectorAll(selector))
        .filter(isElementVisible)
        .slice(0, MAX_INTERACTIVE_ELEMENTS)
        .map((element, index) => ({
            element,
            summary: elementSummary(element, index)
        }));
}

function elementSummary(element, index) {
    return {
        nodeId: `snapshot-${index + 1}`,
        tagName: element.tagName.toLowerCase(),
        role: element.getAttribute("role"),
        type: element.getAttribute("type"),
        text: truncateText(element.innerText || element.value || element.getAttribute("aria-label") || "", 300),
        label: accessibleLabel(element),
        href: element.href || null,
        disabled: isElementDisabled(element),
        selector: cssPath(element),
        rect: elementRect(element)
    };
}

function runDOMCuaAction(request) {
    const { element, summary } = findActionTarget(request);
    if (isElementDisabled(element)) {
        throw new Error(`SpiderWeb could not run ${request.action} because target ${summary.nodeId} is disabled.`);
    }

    element.scrollIntoView({ block: "center", inline: "center", behavior: "auto" });

    switch (request.action) {
    case "click":
        element.focus({ preventScroll: true });
        element.click();
        break;
    case "type":
    case "fill":
        setElementText(element, request.text ?? request.value ?? "");
        break;
    default:
        throw new Error(`SpiderWeb could not run unsupported DOM CUA action: ${request.action}`);
    }

    return {
        kind: "savannah.domCuaActionResult",
        protocolVersion: PROTOCOL_VERSION,
        action: request.action,
        completedAt: new Date().toISOString(),
        target: summary,
        url: window.location.href,
        title: document.title
    };
}

function findActionTarget(request) {
    if (typeof request.selector === "string" && request.selector.length > 0) {
        const element = document.querySelector(request.selector);
        if (!element || !isElementVisible(element)) {
            throw new Error(`SpiderWeb could not find a visible element for selector: ${request.selector}`);
        }

        return {
            element,
            summary: elementSummary(element, 0)
        };
    }

    const nodeId = request.nodeId ?? request.node_id;
    if (typeof nodeId !== "string" || nodeId.length === 0) {
        throw new Error("SpiderWeb could not run a DOM CUA action because nodeId or selector was missing.");
    }

    const record = interactiveElementRecords()
        .find((candidate) => candidate.summary.nodeId === nodeId);
    if (!record) {
        throw new Error(`SpiderWeb could not find a visible interactive element for nodeId: ${nodeId}`);
    }

    return record;
}

function setElementText(element, text) {
    const value = String(text);

    if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
        element.focus({ preventScroll: true });
        element.value = value;
        element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        return;
    }

    if (element.isContentEditable) {
        element.focus({ preventScroll: true });
        element.textContent = value;
        element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        return;
    }

    throw new Error(`SpiderWeb could not type into ${element.tagName.toLowerCase()} because it is not an editable element.`);
}

function isElementVisible(element) {
    const rect = element.getBoundingClientRect();
    const style = window.getComputedStyle(element);
    return rect.width > 0
        && rect.height > 0
        && style.visibility !== "hidden"
        && style.display !== "none"
        && Number(style.opacity) !== 0;
}

function isElementDisabled(element) {
    return Boolean(element.disabled) || element.getAttribute("aria-disabled") === "true";
}

function accessibleLabel(element) {
    const ariaLabel = element.getAttribute("aria-label");
    if (ariaLabel) {
        return ariaLabel;
    }

    if (element.id) {
        const label = document.querySelector(`label[for="${CSS.escape(element.id)}"]`);
        if (label?.innerText) {
            return label.innerText.trim();
        }
    }

    return element.getAttribute("title") || null;
}

function elementRect(element) {
    const rect = element.getBoundingClientRect();
    return {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height
    };
}

function cssPath(element) {
    const parts = [];
    let current = element;

    while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.documentElement) {
        const parent = current.parentElement;
        const tagName = current.tagName.toLowerCase();
        if (current.id) {
            parts.unshift(`${tagName}#${CSS.escape(current.id)}`);
            break;
        }

        const siblings = parent
            ? Array.from(parent.children).filter((sibling) => sibling.tagName === current.tagName)
            : [];
        const index = siblings.indexOf(current) + 1;
        parts.unshift(siblings.length > 1 ? `${tagName}:nth-of-type(${index})` : tagName);
        current = parent;
    }

    return parts.join(" > ");
}

function truncateText(value, maxLength) {
    if (typeof value !== "string") {
        return "";
    }

    const normalized = value.replace(/\s+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
    if (normalized.length <= maxLength) {
        return normalized;
    }

    return `${normalized.slice(0, Math.max(0, maxLength - 3))}...`;
}
