function setupTaskResultModal() {
  const modal = document.getElementById("task-result-modal");
  if (!modal) return;

  const resultSelect = document.getElementById("task-result-value");
  const reasonGroup = document.getElementById("task-result-reason-group");
  const reasonInput = document.getElementById("task-result-reason");
  const confirmButton = document.getElementById("task-result-confirm");
  const suggestionButtons = modal.querySelectorAll("[data-task-result-suggestion]");
  let resolver = null;

  const updateReasonVisibility = () => {
    const incomplete = resultSelect.value === "incomplete";
    reasonGroup.classList.toggle("hidden", !incomplete);
    reasonInput.required = incomplete;
    if (!incomplete) reasonInput.value = "";
  };

  const close = () => {
    modal.classList.add("hidden");
    modal.setAttribute("aria-hidden", "true");
  };

  const contextWrap = document.getElementById("task-result-modal-context");
  const contextTitleEl = document.getElementById("task-result-modal-task-title");
  const contextProjectEl = document.getElementById("task-result-modal-project-name");

  const open = (context = {}) => {
    resultSelect.value = "complete";
    reasonInput.value = "";
    updateReasonVisibility();

    const taskTitle = (context.taskTitle || "").trim();
    const projectName = (context.projectName || "").trim();
    if (contextWrap && contextTitleEl && contextProjectEl) {
      if (taskTitle || projectName) {
        contextWrap.classList.remove("hidden");
        contextTitleEl.textContent = taskTitle || "—";
        contextProjectEl.textContent = projectName || "—";
      } else {
        contextWrap.classList.add("hidden");
      }
    }

    modal.classList.remove("hidden");
    modal.setAttribute("aria-hidden", "false");
  };

  const bindCloseHandlers = () => {
    modal.querySelectorAll("[data-task-result-modal-close]").forEach((el) => {
      el.addEventListener("click", () => {
        close();
        if (resolver) resolver(null);
        resolver = null;
      });
    });
  };

  const prompt = (context = {}) =>
    new Promise((resolve) => {
      resolver = resolve;
      open(context);
    });

  resultSelect.addEventListener("change", updateReasonVisibility);
  suggestionButtons.forEach((button) => {
    button.addEventListener("click", () => {
      reasonInput.value = button.dataset.taskResultSuggestion || "";
      reasonInput.focus();
    });
  });
  bindCloseHandlers();

  confirmButton.addEventListener("click", () => {
    if (resultSelect.value === "incomplete" && !reasonInput.value.trim()) {
      reasonInput.reportValidity();
      return;
    }

    close();
    if (resolver) {
      resolver({
        result: resultSelect.value,
        result_reason: reasonInput.value.trim()
      });
      resolver = null;
    }
  });

  const addHidden = (form, name, value) => {
    let input = form.querySelector(`input[name="${name}"]`);
    if (!input) {
      input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      form.appendChild(input);
    }
    input.value = value || "";
  };

  document.addEventListener("submit", async (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    if (form.dataset.taskResultHandled === "true") return;
    if (!/\/tasks\/\d+\/toggle/.test(form.action)) return;

    const hasCompleteMarker = form.dataset.taskCompleted === "false";
    if (!hasCompleteMarker) return;

    event.preventDefault();
    const outcome = await prompt({
      taskTitle: form.dataset.taskTitle,
      projectName: form.dataset.projectName
    });
    if (!outcome) return;

    addHidden(form, "task_result[result]", outcome.result);
    addHidden(form, "task_result[result_reason]", outcome.result_reason);

    form.dataset.taskResultHandled = "true";
    form.requestSubmit();
  });

  window.promptTaskResult = prompt;
}

document.addEventListener("DOMContentLoaded", setupTaskResultModal);
