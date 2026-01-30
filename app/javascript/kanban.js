import {
  getFilterState,
  saveFilterState as persistFilterState,
  restoreFilterState as loadPersistedState,
  applyFilterState as applyPersistedState,
  applyProjectIdFromUrl
} from "kanban_filter_persistence";
import Sortable from "sortablejs";

document.addEventListener("DOMContentLoaded", function () {
  const kanbanI18n = JSON.parse(
    document.querySelector("[data-kanban-i18n]")?.dataset?.kanbanI18n || "{}"
  );
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

  document.querySelectorAll(".kanban-column").forEach(function (column) {
    new Sortable(column.querySelector(".kanban-tasks"), {
      group: "tasks",
      animation: 150,
      ghostClass: "bg-gray-200",
      onEnd: function (evt) {
        const taskId = evt.item.dataset.taskId;
        const newStatus = evt.to.closest(".kanban-column").dataset.status;
        updateTaskStatus(taskId, newStatus);
      }
    });
    new Sortable(column, {
      group: "tasks",
      animation: 150,
      ghostClass: "bg-gray-200",
      draggable: ".kanban-tasks > *",
      onEnd: function (evt) {
        const taskId = evt.item.dataset.taskId;
        const newStatus = column.dataset.status;
        updateTaskStatus(taskId, newStatus);
      }
    });
  });

  function loadTasks() {
    if (isLoading) return;
    isLoading = true;

    document.querySelectorAll(".kanban-column").forEach((column) => {
      const tasksContainer = column.querySelector(".kanban-tasks");
      const allCards = column.querySelectorAll(".bg-white");
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

    return `
      <div class="surface rounded-lg shadow p-2 cursor-move ${getProjectColorClasses(task.project_color)}" data-task-id="${task.id}">
        <div class="flex justify-between items-start mb-1">
          <h4 class="font-medium text-sm text-gray-900">
            <a href="/tasks/${task.id}" class="hover:text-blue-600 hover:underline">${truncateText(task.title, 20, 20, 4)}</a>
          </h4>
          <span class="px-1.5 py-0.5 text-xs rounded-full ${
            task.priority === "high"
              ? "bg-red-100 text-red-800"
              : task.priority === "medium"
                ? "bg-yellow-100 text-yellow-800"
                : task.priority === "leisure"
                  ? "bg-purple-100 text-purple-800"
                  : "bg-green-100 text-green-800"
          }">
            ${task.priority}
          </span>
        </div>
        <p class="text-xs text-gray-600 mb-1 whitespace-pre-line">${truncateText(task.description, 40, 40, 10)}</p>
        <div class="flex justify-between items-center text-xs text-gray-500">
          <span>${task.project}</span>
          <span>${new Date(task.updated_at).toLocaleDateString()}</span>
        </div>
      </div>
    `;
  }

  function updateTaskStatus(taskId, newStatus) {
    const statusMapping = {
      not_started: "Not Started",
      investigations: "To Investigate",
      in_progress: "In Progress",
      ready_to_test: "Ready to Test",
      complete: "Complete"
    };

    fetch(`/tasks/${taskId}?kanban=true`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
          .content
      },
      body: JSON.stringify({
        task: { status_name: statusMapping[newStatus] }
      })
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
