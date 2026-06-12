/**
 * Escape keyboard navigation shortcut.
 * Enabled when the page defines data-escape-to-url or data-escape-to-kanban-url.
 * Escape inside a text field is left to the browser (blur/clear); no navigation.
 */
export function shouldIgnoreEscapeTarget(target) {
  if (!target || !(target instanceof Element)) return false;

  const tagName = target.tagName.toLowerCase();
  if (["input", "textarea", "select"].includes(tagName)) return true;
  if (target.isContentEditable) return true;
  if (target.getAttribute("contenteditable") === "true") return true;

  return false;
}

export function escapeNavigationUrl(container) {
  if (!container) return null;
  return container.dataset.escapeToUrl || container.dataset.escapeToKanbanUrl || null;
}

export function setupEscapeToKanbanShortcut(doc = document, win = window) {
  const container = doc.querySelector("[data-escape-to-url], [data-escape-to-kanban-url]");
  if (!container) return false;

  const destination = escapeNavigationUrl(container);
  if (!destination) return false;

  doc.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    if (shouldIgnoreEscapeTarget(event.target)) return;

    win.location.assign(destination);
  });

  return true;
}

if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", () => {
    setupEscapeToKanbanShortcut();
  });
}
