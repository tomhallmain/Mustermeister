const {
  shouldIgnoreEscapeTarget,
  escapeNavigationUrl,
  setupEscapeToKanbanShortcut,
} = require("../../app/javascript/escape_to_kanban.js");

describe("escape_to_kanban", () => {
  test("shouldIgnoreEscapeTarget returns true for form fields", () => {
    expect(shouldIgnoreEscapeTarget(document.createElement("input"))).toBe(true);
    expect(shouldIgnoreEscapeTarget(document.createElement("textarea"))).toBe(true);
    expect(shouldIgnoreEscapeTarget(document.createElement("select"))).toBe(true);
  });

  test("shouldIgnoreEscapeTarget returns true for contenteditable", () => {
    const editable = document.createElement("div");
    editable.setAttribute("contenteditable", "true");

    expect(shouldIgnoreEscapeTarget(editable)).toBe(true);
  });

  test("setupEscapeToKanbanShortcut navigates on escape", () => {
    document.body.innerHTML = '<div data-escape-to-kanban-url="/kanban"></div>';
    const assign = jest.fn();
    const mockWindow = { location: { assign } };

    const initialized = setupEscapeToKanbanShortcut(document, mockWindow);
    expect(initialized).toBe(true);

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(assign).toHaveBeenCalledWith("/kanban");
  });

  test("setupEscapeToKanbanShortcut ignores escape inside input", () => {
    document.body.innerHTML = '<div data-escape-to-kanban-url="/kanban"></div><input id="q" />';
    const assign = jest.fn();
    const mockWindow = { location: { assign } };
    const input = document.getElementById("q");

    setupEscapeToKanbanShortcut(document, mockWindow);

    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(assign).not.toHaveBeenCalled();
  });

  test("setupEscapeToKanbanShortcut navigates on escape with data-escape-to-url", () => {
    document.body.innerHTML = '<div data-escape-to-url="/tasks/42"></div>';
    const assign = jest.fn();
    const mockWindow = { location: { assign } };

    setupEscapeToKanbanShortcut(document, mockWindow);

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(assign).toHaveBeenCalledWith("/tasks/42");
  });

  test("setupEscapeToKanbanShortcut ignores escape inside textarea", () => {
    document.body.innerHTML = '<div data-escape-to-url="/tasks/42"></div><textarea id="desc"></textarea>';
    const assign = jest.fn();
    const mockWindow = { location: { assign } };
    const textarea = document.getElementById("desc");

    setupEscapeToKanbanShortcut(document, mockWindow);

    textarea.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(assign).not.toHaveBeenCalled();
  });

  test("escapeNavigationUrl prefers data-escape-to-url", () => {
    const container = document.createElement("div");
    container.dataset.escapeToUrl = "/tasks/1";
    container.dataset.escapeToKanbanUrl = "/kanban";

    expect(escapeNavigationUrl(container)).toBe("/tasks/1");
  });
});
