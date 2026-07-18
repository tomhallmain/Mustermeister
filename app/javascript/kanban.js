import {
  getFilterState,
  saveFilterState as persistFilterState,
  restoreFilterState as loadPersistedState,
  applyFilterState as applyPersistedState,
  applyProjectIdFromUrl
} from "kanban_filter_persistence";
import { setupKanbanTaskContextMenu } from "kanban_context_menu";
import Sortable from "sortablejs";

document.addEventListener("DOMContentLoaded", function () {
  const kanbanI18n = JSON.parse(
    document.querySelector("[data-kanban-i18n]")?.dataset?.kanbanI18n || "{}"
  );
  setupKanbanTaskContextMenu(document, window, { kanbanI18n });
  const projectFilter = document.getElementById("project-filter");
  const priorityFilter = document.getElementById("priority-filter");
  const sortBy = document.getElementById("sort-by");
  const updatedWithinDays = document.getElementById("updated-within-days");
  const showAllCompleted = document.getElementById("show-all-completed");
  const showAllCompletedBtn = document.getElementById("show-all-completed-btn");
  const showAllCompletedText = document.getElementById("show-all-completed-text");
  const searchInput = document.getElementById("search-input");

  const elements = {
    projectFilter,
    priorityFilter,
    sortBy,
    updatedWithinDays,
    showAllCompleted,
    searchInput
  };

  let currentPage = 1;
  let isLoading = false;
  let allTasks = {};

  function saveFilterState() {
    persistFilterState(getFilterState(elements), sessionStorage);
  }

  function restoreFilterState() {
    const state = loadPersistedState(sessionStorage);
    if (!state) return false;
    applyPersistedState(state, elements);
    return true;
  }

  function updateShowCompletedButton() {
    const isChecked = showAllCompleted.checked;
    if (isChecked) {
      showAllCompletedBtn.className =
        "flex items-center space-x-2 px-4 py-2 rounded-md bg-blue-100 text-blue-700 hover:bg-opacity-80 text-xs";
      showAllCompletedText.textContent =
        kanbanI18n.hide_completed || "Hide Completed";
    } else {
      showAllCompletedBtn.className =
        "flex items-center space-x-2 px-4 py-2 rounded-md bg-gray-100 text-gray-700 hover:bg-opacity-80 text-xs";
      showAllCompletedText.textContent =
        kanbanI18n.show_completed || "Show Completed";
    }
  }

  function isSessionExpiredError(error, response) {
    if (response && (response.status === 401 || response.status === 403)) {
      return true;
    }
    if (error) {
      const errorMessage = error.message ? error.message.toLowerCase() : "";
      const errorName = error.name ? error.name.toLowerCase() : "";
      return (
        errorMessage.includes("failed to fetch") ||
        errorMessage.includes("network error") ||
        errorMessage.includes("connection") ||
        errorName === "typeerror" ||
        errorName === "networkerror"
      );
    }
    return false;
  }

  function handleSessionExpiration(context) {
    console.log(
      `Session expired during ${context}, refreshing page to redirect to login`
    );
    window.location.reload();
  }

  // Plain (non-Sortable) dragover/drop handler covering the whole board, so
  // the browser shows a valid drop cursor everywhere within it - including
  // .kanban-column's own padding and header, which .kanban-tasks doesn't
  // visually cover. This is native HTML5 DnD's actual requirement: an
  // element with dragover.preventDefault() somewhere in the hovered
  // ancestor chain. It does NOT register as a Sortable/group participant,
  // so it can't steal a drop or duplicate a card the way a second Sortable
  // instance did (see below) - it only affects cursor/drop-acceptance, not
  // list membership, which is still governed solely by the one Sortable
  // instance on .kanban-tasks.
  const kanbanBoard = document.getElementById("kanban-board");
  if (kanbanBoard) {
    kanbanBoard.addEventListener("dragover", (e) => e.preventDefault());
    kanbanBoard.addEventListener("drop", (e) => e.preventDefault());
  }

  document.querySelectorAll(".kanban-column").forEach(function (column) {
    // Only one Sortable root per column, on .kanban-tasks itself. A second
    // instance used to also be rooted on the parent .kanban-column, sharing
    // the same group: "tasks" with one nested inside the other - SortableJS
    // would occasionally let the outer instance win the drop and insert the
    // card as a sibling of .kanban-tasks instead of inside it, a stray card
    // the innerHTML re-render in loadTasks() never touches, so it persisted
    // until a full page reload.
    //
    // Native HTML5 DnD (SortableJS's default) is used here rather than
    // forceFallback: forceFallback's own pointer-based hit-testing turned
    // out to unreliably resolve evt.to to the wrong (source) list when
    // dragging across columns - confirmed via diagnostic logging, evt.to
    // kept reporting the origin column instead of the drop target. Native
    // mode's evt.to was already proven correct (this is how status changes
    // worked, pre-stray-card-fix); the dragover listener above is what
    // makes native mode viable with only one Sortable instance per column.
    new Sortable(column.querySelector(".kanban-tasks"), {
      group: "tasks",
      animation: 150,
      ghostClass: "bg-gray-200",
      // Default (5px) only treats a thin margin around an EMPTY list's edge
      // as a valid drop target, not its whole box. .kanban-tasks now has
      // flex-1 (kanban.html.erb) so it stretches to match the tallest
      // column - which can be arbitrarily tall for a large backlog - so
      // this needs to be generously large rather than tied to a fixed
      // min-height, to keep the whole empty column droppable regardless of
      // how tall its stretched siblings make it.
      emptyInsertThreshold: 5000,
      onEnd: function (evt) {
        const taskId = evt.item.dataset.taskId;
        const newStatus = evt.to.closest(".kanban-column").dataset.status;
        updateTaskStatus(taskId, newStatus);
      }
    });
  });

  function loadTasks() {
    if (isLoading) return;
    isLoading = true;

    // Defensive backstop: sweep out any card that ended up outside its
    // .kanban-tasks container (e.g. dropped directly into the column). Cards
    // are identified by [data-task-id] (set in createTaskCard below) rather
    // than a style class, since class names are more likely to drift.
    document.querySelectorAll(".kanban-column").forEach((column) => {
      const tasksContainer = column.querySelector(".kanban-tasks");
      const allCards = column.querySelectorAll("[data-task-id]");
      allCards.forEach((card) => {
        if (!tasksContainer.contains(card)) {
          card.remove();
        }
      });
    });

    const params = new URLSearchParams({
      page: currentPage,
      sort_by: sortBy.value,
      show_all_completed: showAllCompleted.checked
    });
    if (projectFilter.value) params.append("project_id", projectFilter.value);
    if (priorityFilter.value) params.append("priority", priorityFilter.value);
    if (updatedWithinDays.value) {
      params.append("updated_within_days", updatedWithinDays.value);
    }

    fetch(`/kanban/tasks?${params}`)
      .then((response) => {
        if (isSessionExpiredError(null, response)) {
          handleSessionExpiration("loading tasks");
          return;
        }
        return response.json();
      })
      .then((data) => {
        if (data) {
          allTasks = data.tasks;
          filterAndDisplayTasks();
          updatePaginationControls(data.has_more);
        }
        isLoading = false;
      })
      .catch((error) => {
        console.error("Error loading tasks:", error);
        if (isSessionExpiredError(error, null)) {
          handleSessionExpiration("loading tasks");
          return;
        }
        isLoading = false;
      });
  }

  function filterAndDisplayTasks() {
    const searchTerm = searchInput.value.toLowerCase();
    const statusMapping = {
      not_started: ["not_started"],
      investigations: ["to_investigate", "investigated"],
      in_progress: ["in_progress"],
      ready_to_test: ["ready_to_test"],
      complete: ["complete", "closed"]
    };

    Object.entries(statusMapping).forEach(([displayStatus, backendStatuses]) => {
      const column = document.querySelector(
        `.kanban-tasks[data-status="${displayStatus}"]`
      );
      if (column) {
        let tasks = backendStatuses.flatMap((status) => allTasks[status] || []);
        if (searchTerm) {
          tasks = tasks.filter(
            (task) =>
              task.title.toLowerCase().includes(searchTerm) ||
              task.description.toLowerCase().includes(searchTerm) ||
              task.project.toLowerCase().includes(searchTerm)
          );
        }
        column.innerHTML = tasks.map((task) => createTaskCard(task)).join("");
      }
    });
  }

  function updatePaginationControls(hasMore) {
    document
      .querySelectorAll(".pagination-container")
      .forEach((container) => container.remove());

    document.querySelectorAll(".kanban-column").forEach((column) => {
      const paginationContainer = document.createElement("div");
      paginationContainer.className = "pagination-container mt-2 space-y-2";

      if (currentPage > 1) {
        const prevBtn = document.createElement("button");
        prevBtn.className =
          "pagination-btn w-full px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-indigo-600 bg-indigo-100 hover:bg-indigo-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500";
        prevBtn.innerHTML = `
          <svg class="h-4 w-4 inline-block mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
          ${kanbanI18n.previous_page || "Previous Page"}
        `;
        prevBtn.onclick = () => {
          currentPage--;
          loadTasks();
        };
        paginationContainer.appendChild(prevBtn);

        const resetBtn = document.createElement("button");
        resetBtn.className =
          "pagination-btn w-full px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-indigo-600 bg-indigo-100 hover:bg-indigo-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500";
        resetBtn.innerHTML = `
          <svg class="h-4 w-4 inline-block mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          ${kanbanI18n.reset_to_first_page || "Reset to First Page"}
        `;
        resetBtn.onclick = () => {
          currentPage = 1;
          loadTasks();
        };
        paginationContainer.appendChild(resetBtn);
      }

      if (hasMore) {
        const loadMoreBtn = document.createElement("button");
        loadMoreBtn.className =
          "pagination-btn w-full px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-indigo-600 bg-indigo-100 hover:bg-indigo-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500";
        loadMoreBtn.innerHTML = `
          ${kanbanI18n.load_more || "Load More"}
          <svg class="h-4 w-4 inline-block ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        `;
        loadMoreBtn.onclick = () => {
          currentPage++;
          loadTasks();
        };
        paginationContainer.appendChild(loadMoreBtn);
      }

      const tasksContainer = column.querySelector(".kanban-tasks");
      tasksContainer.after(paginationContainer);
    });
  }

  function createTaskCard(task) {
    const escapeHtmlAttr = (str) =>
      String(str ?? "")
        .replace(/&/g, "&amp;")
        .replace(/"/g, "&quot;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");

    const truncateText = (text, maxWordLength, maxLineLength, maxLines) => {
      if (!text) return "";
      const words = text.split(/\s+/);
      let currentLineLength = 0;
      let lineCount = 1;
      const truncatedWords = [];
      for (const word of words) {
        if (word.length >= maxWordLength) {
          truncatedWords.push(
            word.substring(0, maxWordLength - 10) + "..."
          );
          return truncatedWords.join(" ");
        }
        const wordLength = word.length + 1;
        if (currentLineLength + wordLength > maxLineLength) {
          lineCount++;
          currentLineLength = wordLength;
        } else {
          currentLineLength += wordLength;
        }
        if (lineCount > maxLines) {
          return truncatedWords.join(" ") + "...";
        }
        truncatedWords.push(word);
      }
      return truncatedWords.join(" ");
    };

    const getProjectColorClasses = (projectColor) => {
      if (!projectColor) return "";
      switch (projectColor) {
        case "red":
          return "border-l-4 border-l-red-500 bg-red-50";
        case "orange":
          return "border-l-4 border-l-orange-500 bg-orange-50";
        case "yellow":
          return "border-l-4 border-l-yellow-500 bg-yellow-50";
        case "green":
          return "border-l-4 border-l-green-500 bg-green-50";
        case "blue":
          return "border-l-4 border-l-blue-500 bg-blue-50";
        case "purple":
          return "border-l-4 border-l-purple-500 bg-purple-50";
        case "pink":
          return "border-l-4 border-l-pink-500 bg-pink-50";
        case "gray":
          return "border-l-4 border-l-gray-500 bg-gray-50";
        default:
          return "";
      }
    };

    const getCategoryBadgeClasses = (categoryColor) => {
      switch (categoryColor) {
        case "red":
          return "bg-red-100 text-red-800";
        case "orange":
          return "bg-orange-100 text-orange-800";
        case "yellow":
          return "bg-yellow-100 text-yellow-800";
        case "green":
          return "bg-green-100 text-green-800";
        case "blue":
          return "bg-blue-100 text-blue-800";
        case "purple":
          return "bg-purple-100 text-purple-800";
        case "pink":
          return "bg-pink-100 text-pink-800";
        case "gray":
          return "bg-gray-100 text-gray-800";
        default:
          return "bg-teal-100 text-teal-800";
      }
    };

    const translatedPriority =
      kanbanI18n?.priorities?.[task.priority] || task.priority;

    return `
      <div class="surface rounded-lg shadow p-2 cursor-move select-none ${getProjectColorClasses(task.project_color)}" data-task-id="${task.id}" data-task-title="${escapeHtmlAttr(task.title)}" data-project-name="${escapeHtmlAttr(task.project)}">
        <div class="flex justify-between items-start mb-1">
          <h4 class="font-medium text-sm text-gray-900">
            <a href="/tasks/${task.id}" class="hover:text-blue-600 hover:underline">${truncateText(task.title, 20, 20, 4)}</a>
          </h4>
          <div class="flex flex-col items-end gap-0.5">
            <span class="px-1.5 py-0.5 text-xs rounded-full ${
              task.priority === "high"
                ? "bg-red-100 text-red-800"
                : task.priority === "medium"
                  ? "bg-yellow-100 text-yellow-800"
                  : task.priority === "leisure"
                    ? "bg-purple-100 text-purple-800"
                    : "bg-green-100 text-green-800"
            }">
              ${translatedPriority}
            </span>
            ${
              task.category
                ? `<span class="px-1.5 py-0.5 text-xs rounded-full ${getCategoryBadgeClasses(task.category_color)}">${escapeHtmlAttr(task.category)}</span>`
                : ""
            }
          </div>
        </div>
        <p class="text-xs text-gray-600 mb-1 whitespace-pre-line">${truncateText(task.description, 40, 40, 10)}</p>
        <div class="flex justify-between items-center text-xs text-gray-500">
          <span>${task.project}</span>
          <span>${new Date(task.updated_at).toLocaleDateString()}</span>
        </div>
      </div>
    `;
  }

  async function updateTaskStatus(taskId, newStatus) {
    const statusMapping = {
      not_started: "Not Started",
      investigations: "To Investigate",
      in_progress: "In Progress",
      ready_to_test: "Ready to Test",
      complete: "Complete"
    };

    const requestPayload = {
      task: { status_name: statusMapping[newStatus] }
    };

    if (newStatus === "complete" && typeof window.promptTaskResult === "function") {
      const card = document.querySelector(`[data-task-id="${taskId}"]`);
      const outcome = await window.promptTaskResult({
        taskTitle: card?.dataset?.taskTitle,
        projectName: card?.dataset?.projectName
      });
      if (!outcome) {
        loadTasks();
        return;
      }
      requestPayload.task_result = outcome;
    }

    fetch(`/tasks/${taskId}?kanban=true`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
          .content
      },
      body: JSON.stringify(requestPayload)
    })
      .then((response) => {
        if (!response.ok) {
          if (isSessionExpiredError(null, response)) {
            handleSessionExpiration("updating task status");
            return;
          }
          return response.json().then((data) => {
            throw new Error(data.error || "Failed to update task status");
          });
        }
        loadTasks();
      })
      .catch((error) => {
        console.error("Error updating task status:", error);
        if (isSessionExpiredError(error, null)) {
          handleSessionExpiration("updating task status");
          return;
        }
        alert(error.message);
        loadTasks();
      });
  }

  projectFilter.addEventListener("change", function () {
    saveFilterState();
    loadTasks();
  });
  priorityFilter.addEventListener("change", function () {
    if (this.value && sortBy.value === "priority") {
      sortBy.value = "updated_at";
    }
    saveFilterState();
    loadTasks();
  });
  sortBy.addEventListener("change", function () {
    saveFilterState();
    loadTasks();
  });
  updatedWithinDays.addEventListener("change", function () {
    saveFilterState();
    loadTasks();
  });
  showAllCompleted.addEventListener("change", function () {
    updateShowCompletedButton();
    saveFilterState();
    loadTasks();
  });
  showAllCompletedBtn.addEventListener("click", function () {
    showAllCompleted.checked = !showAllCompleted.checked;
    updateShowCompletedButton();
    saveFilterState();
    loadTasks();
  });
  searchInput.addEventListener("input", function () {
    filterAndDisplayTasks();
    saveFilterState();
  });

  restoreFilterState();
  // URL project_id wins over sessionStorage (e.g. "View on Kanban Board" from project page)
  if (applyProjectIdFromUrl(elements, window.location.search)) {
    saveFilterState();
  }
  updateShowCompletedButton();
  loadTasks();
});
