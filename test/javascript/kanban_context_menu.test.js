const {
  findKanbanTaskCard,
  copyTextToClipboard,
  setupKanbanTaskContextMenu,
} = require("../../app/javascript/kanban_context_menu.js");

describe("kanban_context_menu", () => {
  test("findKanbanTaskCard returns card inside kanban column", () => {
    document.body.innerHTML = `
      <div class="kanban-tasks">
        <div data-task-id="1" data-task-title="Fix login bug">
          <a href="/tasks/1">Fix login bug</a>
        </div>
      </div>
    `;
    const link = document.querySelector("a");

    expect(findKanbanTaskCard(link)?.dataset.taskTitle).toBe("Fix login bug");
  });

  test("findKanbanTaskCard ignores cards outside kanban columns", () => {
    document.body.innerHTML =
      '<div data-task-id="1" data-task-title="Elsewhere"><span id="x"></span></div>';
    expect(findKanbanTaskCard(document.getElementById("x"))).toBeNull();
  });

  test("copyTextToClipboard uses clipboard API when available", async () => {
    const writeText = jest.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });

    const copied = await copyTextToClipboard("Task title");

    expect(copied).toBe(true);
    expect(writeText).toHaveBeenCalledWith("Task title");
  });

  test("setupKanbanTaskContextMenu copies title from context menu click", async () => {
    document.body.innerHTML = `
      <div class="kanban-tasks">
        <div data-task-id="42" data-task-title="Ship feature">
          <span id="card-body">Ship feature</span>
        </div>
      </div>
    `;
    const writeText = jest.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });

    setupKanbanTaskContextMenu(document, window, {
      kanbanI18n: { copy_task_title: "Copy title", title_copied: "Copied!" },
    });

    const cardBody = document.getElementById("card-body");
    cardBody.dispatchEvent(
      new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: 10, clientY: 10 })
    );

    const menuButton = document.querySelector("#kanban-task-context-menu button");
    expect(menuButton.textContent).toBe("Copy title");

    menuButton.click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(writeText).toHaveBeenCalledWith("Ship feature");
    const toast = document.getElementById("kanban-copy-toast");
    expect(toast).not.toBeNull();
    expect(toast.textContent).toBe("Copied!");
  });
});
