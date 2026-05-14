const PROTOCOL_VERSION = "0.1.0";
const MAX_VISIBLE_TEXT_LENGTH = 20000;
const MAX_INTERACTIVE_ELEMENTS = 100;

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    console.log("SpiderWeb content script received request: ", request);

    if (request?.kind !== "savannah.getPageSnapshot") {
        return undefined;
    }

    return Promise.resolve(collectPageSnapshot(request));
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

    return Array.from(document.querySelectorAll(selector))
        .filter(isElementVisible)
        .slice(0, MAX_INTERACTIVE_ELEMENTS)
        .map((element, index) => ({
            nodeId: `snapshot-${index + 1}`,
            tagName: element.tagName.toLowerCase(),
            role: element.getAttribute("role"),
            type: element.getAttribute("type"),
            text: truncateText(element.innerText || element.value || element.getAttribute("aria-label") || "", 300),
            label: accessibleLabel(element),
            href: element.href || null,
            disabled: Boolean(element.disabled) || element.getAttribute("aria-disabled") === "true",
            selector: cssPath(element),
            rect: elementRect(element)
        }));
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
