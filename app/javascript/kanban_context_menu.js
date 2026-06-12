export function findKanbanTaskCard(target) {
  if (!target || !(target instanceof Element)) return null;

  const card = target.closest("[data-task-id][data-task-title]");
  if (!card || !card.closest(".kanban-tasks")) return null;

  return card;
}

export async function copyTextToClipboard(text, doc = document) {
  const trimmed = String(text ?? "");
  if (!trimmed) return false;

  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(trimmed);
      return true;
    }
  } catch (_error) {
    // fall through to execCommand
  }

  const textarea = doc.createElement("textarea");
  textarea.value = trimmed;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.left = "-9999px";
  doc.body.appendChild(textarea);
  textarea.select();
  const copied = doc.execCommand("copy");
  textarea.remove();
  return copied;
}

export function setupKanbanTaskContextMenu(doc, win, { kanbanI18n = {} } = {}) {
  const menu = doc.createElement("div");
  menu.id = "kanban-task-context-menu";
  menu.className =
    "hidden fixed z-50 min-w-[10rem] rounded-md border border-gray-200 surface shadow-lg py-1";
  menu.setAttribute("role", "menu");

  const copyLabel = kanbanI18n.copy_task_title || "Copy title";
  const button = doc.createElement("button");
  button.type = "button";
  button.className =
    "kanban-context-menu-item block w-full text-left px-3 py-2 text-sm";
  button.textContent = copyLabel;
  button.setAttribute("role", "menuitem");
  menu.appendChild(button);
  doc.body.appendChild(menu);

  let activeCard = null;
  let toastTimer = null;

  const hideMenu = () => {
    menu.classList.add("hidden");
    activeCard = null;
  };

  const showToast = (message) => {
    let toast = doc.getElementById("kanban-copy-toast");
    if (!toast) {
      toast = doc.createElement("div");
      toast.id = "kanban-copy-toast";
      toast.className =
        "fixed bottom-4 right-4 z-50 px-3 py-2 rounded-md bg-gray-900 text-white text-sm shadow-lg";
      doc.body.appendChild(toast);
    }
    toast.textContent = message;
    toast.classList.remove("hidden");
    if (toastTimer) win.clearTimeout(toastTimer);
    toastTimer = win.setTimeout(() => toast.classList.add("hidden"), 2000);
  };

  const positionMenu = (clientX, clientY) => {
    menu.classList.remove("hidden");
    menu.style.left = "0px";
    menu.style.top = "0px";

    const margin = 8;
    const rect = menu.getBoundingClientRect();
    let x = clientX;
    let y = clientY;

    if (x + rect.width > win.innerWidth - margin) {
      x = Math.max(margin, win.innerWidth - rect.width - margin);
    }
    if (y + rect.height > win.innerHeight - margin) {
      y = Math.max(margin, win.innerHeight - rect.height - margin);
    }

    menu.style.left = `${x}px`;
    menu.style.top = `${y}px`;
  };

  doc.addEventListener("click", hideMenu);
  doc.addEventListener("scroll", hideMenu, true);
  doc.addEventListener("keydown", (event) => {
    if (event.key === "Escape") hideMenu();
  });

  doc.addEventListener("contextmenu", (event) => {
    const card = findKanbanTaskCard(event.target);
    if (!card) return;

    event.preventDefault();
    activeCard = card;
    positionMenu(event.clientX, event.clientY);
  });

  button.addEventListener("click", async (event) => {
    event.stopPropagation();
    if (!activeCard) return;

    const title = activeCard.dataset.taskTitle || "";
    const copied = await copyTextToClipboard(title, doc);
    hideMenu();

    if (copied) {
      showToast(kanbanI18n.title_copied || "Title copied");
    }
  });

  return { hideMenu };
}
