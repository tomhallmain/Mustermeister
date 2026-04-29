/**
 * Escape-to-kanban keyboard shortcut.
 * Enabled only when the page defines data-escape-to-kanban-url.
 */
export function shouldIgnoreEscapeTarget(target) {
  if (!target || !(target instanceof Element)) return false;

  const tagName = target.tagName.toLowerCase();
  if (["input", "textarea", "select"].includes(tagName)) return true;
  if (target.isContentEditable) return true;
  if (target.getAttribute("contenteditable") === "true") return true;

  return false;
}

export function setupEscapeToKanbanShortcut(doc = document, win = window) {
  const container = doc.querySelector("[data-escape-to-kanban-url]");
  if (!container) return false;

  const destination = container.dataset.escapeToKanbanUrl;
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
