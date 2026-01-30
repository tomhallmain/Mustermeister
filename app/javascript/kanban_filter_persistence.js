/**
 * Kanban filter persistence (sessionStorage).
 * Elements and storage are passed in so this module is testable without a DOM.
 */
export const KANBAN_STORAGE_KEY = "kanbanFilters";

/**
 * @param {{ projectFilter: { value: string }, priorityFilter: { value: string }, sortBy: { value: string }, updatedWithinDays: { value: string }, showAllCompleted: { checked: boolean }, searchInput: { value: string } }} elements
 * @returns {{ project_id: string, priority: string, sort_by: string, updated_within_days: string, show_all_completed: boolean, search: string }}
 */
export function getFilterState(elements) {
  return {
    project_id: elements.projectFilter.value,
    priority: elements.priorityFilter.value,
    sort_by: elements.sortBy.value,
    updated_within_days: elements.updatedWithinDays.value,
    show_all_completed: elements.showAllCompleted.checked,
    search: elements.searchInput.value,
  };
}

/**
 * @param {ReturnType<typeof getFilterState>} state
 * @param {{ setItem: (key: string, value: string) => void }} storage
 */
export function saveFilterState(state, storage) {
  if (!storage) return;
  try {
    storage.setItem(KANBAN_STORAGE_KEY, JSON.stringify(state));
  } catch (_e) {}
}

/**
 * @param {{ getItem: (key: string) => string | null }} storage
 * @returns {ReturnType<typeof getFilterState> | null}
 */
export function restoreFilterState(storage) {
  if (!storage) return null;
  try {
    const raw = storage.getItem(KANBAN_STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch (_e) {
    return null;
  }
}

/**
 * @param {ReturnType<typeof getFilterState>} state
 * @param {{ projectFilter: { value: string }, priorityFilter: { value: string }, sortBy: { value: string }, updatedWithinDays: { value: string }, showAllCompleted: { checked: boolean }, searchInput: { value: string } }} elements
 * @returns {boolean}
 */
export function applyFilterState(state, elements) {
  if (!state) return false;
  if (state.project_id !== undefined) elements.projectFilter.value = state.project_id;
  if (state.priority !== undefined) elements.priorityFilter.value = state.priority;
  if (state.sort_by !== undefined) elements.sortBy.value = state.sort_by;
  if (state.updated_within_days !== undefined) elements.updatedWithinDays.value = state.updated_within_days;
  if (state.show_all_completed !== undefined) elements.showAllCompleted.checked = state.show_all_completed;
  if (state.search !== undefined) elements.searchInput.value = state.search;
  return true;
}

/**
 * Apply project_id from URL search string so link-from-project-page overrides sessionStorage.
 * @param {{ projectFilter: { value: string } }} elements
 * @param {string} searchString - e.g. window.location.search
 * @returns {boolean} true if project_id was present and applied
 */
export function applyProjectIdFromUrl(elements, searchString) {
  if (!searchString) return false;
  const params = new URLSearchParams(searchString);
  const id = params.get("project_id");
  if (id == null) return false;
  elements.projectFilter.value = id;
  return true;
}
