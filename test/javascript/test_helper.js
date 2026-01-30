/**
 * Shared test helpers for JavaScript tests.
 * Provides mock objects that implement common interfaces (e.g. Storage, form elements).
 */

/**
 * In-memory Storage-like object (getItem/setItem) for testing persistence without a browser.
 * @returns {{ getItem: (key: string) => string|null, setItem: (key: string, value: string) => void }}
 */
function mockStorage() {
  const store = {};
  return {
    getItem(key) {
      return store[key] ?? null;
    },
    setItem(key, value) {
      store[key] = String(value);
    },
  };
}

/**
 * Mock form elements object for kanban filter persistence tests.
 * Each property is an object with .value (string) or .checked (boolean).
 * @param {Object} [overrides] - Override specific properties (e.g. { projectFilter: { value: "42" } })
 * @returns {Object}
 */
function mockKanbanFilterElements(overrides = {}) {
  return {
    projectFilter: { value: "" },
    priorityFilter: { value: "" },
    sortBy: { value: "updated_at" },
    updatedWithinDays: { value: "" },
    showAllCompleted: { checked: false },
    searchInput: { value: "" },
    ...overrides,
  };
}

module.exports = {
  mockStorage,
  mockKanbanFilterElements,
};
