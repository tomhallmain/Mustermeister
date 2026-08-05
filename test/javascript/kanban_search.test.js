/**
 * Regression: search must not throw when description (or other fields) is null.
 * That shows up especially on the all-projects board, where more tasks lack a
 * description than when a single project is filtered.
 */
const { taskMatchesSearch } = require("../../app/javascript/kanban_search.js");

describe("kanban_search", () => {
  test("matches title, description, or project (case-insensitive)", () => {
    const task = {
      title: "Fix Login",
      description: "Reset password flow",
      project: "Auth Service",
    };

    expect(taskMatchesSearch(task, "login")).toBe(true);
    expect(taskMatchesSearch(task, "password")).toBe(true);
    expect(taskMatchesSearch(task, "auth")).toBe(true);
    expect(taskMatchesSearch(task, "missing")).toBe(false);
  });

  test("does not throw when description is null", () => {
    const task = {
      title: "Untitled chore",
      description: null,
      project: "House",
    };

    expect(() => taskMatchesSearch(task, "chore")).not.toThrow();
    expect(taskMatchesSearch(task, "chore")).toBe(true);
    expect(taskMatchesSearch(task, "house")).toBe(true);
    expect(taskMatchesSearch(task, "absent")).toBe(false);
  });

  test("does not throw when title, description, or project are null/undefined", () => {
    const task = {
      title: null,
      description: undefined,
      project: null,
    };

    expect(() => taskMatchesSearch(task, "x")).not.toThrow();
    expect(taskMatchesSearch(task, "x")).toBe(false);
  });

  test("empty search term matches all tasks", () => {
    expect(
      taskMatchesSearch(
        { title: "A", description: null, project: "B" },
        ""
      )
    ).toBe(true);
  });
});
