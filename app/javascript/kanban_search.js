/**
 * Client-side kanban search matching.
 * Description (and potentially other fields) can be null in the JSON payload
 * from tasks#kanban_tasks, so callers must not call string methods on them
 * directly.
 */

/**
 * @param {{ title?: string | null, description?: string | null, project?: string | null }} task
 * @param {string} searchTerm already lowercased search text; empty means match all
 * @returns {boolean}
 */
export function taskMatchesSearch(task, searchTerm) {
  if (!searchTerm) return true;

  return [task?.title, task?.description, task?.project].some((value) =>
    String(value ?? "")
      .toLowerCase()
      .includes(searchTerm)
  );
}
