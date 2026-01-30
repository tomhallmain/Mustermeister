/**
 * Tests for kanban filter persistence (save/restore round-trip) without a browser.
 */
const {
  KANBAN_STORAGE_KEY,
  getFilterState,
  saveFilterState,
  restoreFilterState,
  applyFilterState,
} = require("../../app/javascript/kanban_filter_persistence.js");
const { mockStorage, mockKanbanFilterElements: mockElements } = require("./test_helper.js");

describe("kanban_filter_persistence", () => {
  test("getFilterState returns current element values", () => {
    const elements = mockElements({
      projectFilter: { value: "42" },
      priorityFilter: { value: "high" },
      sortBy: { value: "priority" },
      updatedWithinDays: { value: "7" },
      showAllCompleted: { checked: true },
      searchInput: { value: "foo" },
    });
    const state = getFilterState(elements);
    expect(state).toEqual({
      project_id: "42",
      priority: "high",
      sort_by: "priority",
      updated_within_days: "7",
      show_all_completed: true,
      search: "foo",
    });
  });

  test("saveFilterState and restoreFilterState round-trip", () => {
    const storage = mockStorage();
    const state = {
      project_id: "1",
      priority: "medium",
      sort_by: "created_at",
      updated_within_days: "14",
      show_all_completed: true,
      search: "bar",
    };
    saveFilterState(state, storage);
    const restored = restoreFilterState(storage);
    expect(restored).toEqual(state);
  });

  test("restoreFilterState returns null when storage is empty", () => {
    const storage = mockStorage();
    expect(restoreFilterState(storage)).toBeNull();
  });

  test("applyFilterState updates elements from state", () => {
    const elements = mockElements();
    const state = {
      project_id: "99",
      priority: "low",
      sort_by: "priority",
      updated_within_days: "30",
      show_all_completed: true,
      search: "baz",
    };
    const applied = applyFilterState(state, elements);
    expect(applied).toBe(true);
    expect(elements.projectFilter.value).toBe("99");
    expect(elements.priorityFilter.value).toBe("low");
    expect(elements.sortBy.value).toBe("priority");
    expect(elements.updatedWithinDays.value).toBe("30");
    expect(elements.showAllCompleted.checked).toBe(true);
    expect(elements.searchInput.value).toBe("baz");
  });

  test("full round-trip: getFilterState -> save -> restore -> applyFilterState", () => {
    const storage = mockStorage();
    const elements = mockElements({
      projectFilter: { value: "5" },
      priorityFilter: { value: "leisure" },
      searchInput: { value: "query" },
    });
    const state = getFilterState(elements);
    saveFilterState(state, storage);
    const freshElements = mockElements();
    const restored = restoreFilterState(storage);
    applyFilterState(restored, freshElements);
    expect(getFilterState(freshElements)).toEqual(state);
  });

  test("persisted value uses KANBAN_STORAGE_KEY", () => {
    const storage = mockStorage();
    saveFilterState({ project_id: "1", priority: "", sort_by: "updated_at", updated_within_days: "", show_all_completed: false, search: "" }, storage);
    expect(storage.getItem(KANBAN_STORAGE_KEY)).toBeTruthy();
    expect(JSON.parse(storage.getItem(KANBAN_STORAGE_KEY)).project_id).toBe("1");
  });
});
