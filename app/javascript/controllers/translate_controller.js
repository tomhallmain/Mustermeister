import { Controller } from "@hotwired/stimulus"

// Translate button opens a confirm modal (rather than firing the LLM call
// immediately) - a translation call can be slow, especially the first time
// a given model is used (Ollama has to load it), so the user should see and
// be able to change which model will be used before triggering it. The
// modal's model field is the shared select+text-input pair
// (shared/_llm_model_field) - the text input is what's actually submitted
// and accepts free text (not just models Ollama already knows about); the paired
// <select>'s options are enriched, non-blockingly, from the existing Task
// Insights Ollama health endpoint once the modal opens - suggestions
// arriving late (or not at all) never blocks confirming, since typing
// directly into the text input is always valid regardless.
//
// Confirming fetches TasksController#translate and shows the result in a
// review panel - deliberately not auto-applied to the task, since an LLM
// translation can be wrong and the user should confirm it too. "Use this
// translation" submits a normal task update form with the translated
// values (see apply()).
export default class extends Controller {
  static targets = ["button", "panel", "title", "description", "error", "modal", "modelInput", "confirmButton"]
  static values = { url: String, updateUrl: String, ollamaHealthUrl: String }

  connect() {
    this.hideError()
    this.hidePanel()
  }

  openModal() {
    this.modalTarget.classList.remove("hidden")
    this.fetchModelSuggestions()
  }

  cancelModal() {
    this.modalTarget.classList.add("hidden")
  }

  fetchModelSuggestions() {
    fetch(this.ollamaHealthUrlValue, {
      method: "GET",
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    })
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => {
        if (data && data.models && data.models.length) {
          this.populateModelSuggestions(data.models)
        } else {
          // Suggestions are a convenience only - the model field already
          // accepts free text, so this isn't shown to the user - but it's
          // worth a console trace, since it's otherwise invisible whether
          // this returned zero models or something else entirely.
          console.warn("Translate: no Ollama model suggestions returned", data)
        }
      })
      .catch((error) => {
        console.warn("Translate: failed to fetch Ollama model suggestions", error)
      })
  }

  populateModelSuggestions(models) {
    const select = document.getElementById(`${this.modelInputTarget.id}-select`)
    if (!select) return

    const previousValue = select.value
    select.innerHTML = ""

    const blankOption = document.createElement("option")
    blankOption.value = ""
    select.appendChild(blankOption)

    models.forEach((model) => {
      const option = document.createElement("option")
      option.value = model
      option.textContent = model
      if (model === previousValue) option.selected = true
      select.appendChild(option)
    })

    if (!this.modelInputTarget.value) this.modelInputTarget.value = models[0]
  }

  confirm() {
    this.confirmButtonTarget.disabled = true
    this.hideError()

    const params = new URLSearchParams({ model: this.modelInputTarget.value })

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.csrfToken(),
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json"
      },
      body: params.toString()
    })
      .then((response) => response.json().then((data) => ({ ok: response.ok, data })))
      .then(({ ok, data }) => {
        this.cancelModal()
        if (!ok || data.error) {
          this.showError(data.error || this.errorTarget.dataset.genericError)
          return
        }
        this.titleTarget.textContent = data.title
        this.descriptionTarget.textContent = data.description
        this.showPanel()
      })
      .catch(() => {
        this.cancelModal()
        this.showError(this.errorTarget.dataset.genericError)
      })
      .finally(() => {
        this.confirmButtonTarget.disabled = false
      })
  }

  apply() {
    const form = document.createElement("form")
    form.method = "POST"
    form.action = this.updateUrlValue
    form.style.display = "none"

    form.appendChild(this.hiddenField("_method", "patch"))
    form.appendChild(this.hiddenField("authenticity_token", this.csrfToken()))
    form.appendChild(this.hiddenField("task[title]", this.titleTarget.textContent))

    const descriptionField = document.createElement("textarea")
    descriptionField.name = "task[description]"
    descriptionField.textContent = this.descriptionTarget.textContent
    form.appendChild(descriptionField)

    document.body.appendChild(form)
    form.submit()
  }

  dismiss() {
    this.hidePanel()
  }

  showPanel() {
    this.panelTarget.classList.remove("hidden")
  }

  hidePanel() {
    this.panelTarget.classList.add("hidden")
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  hideError() {
    this.errorTarget.classList.add("hidden")
  }

  hiddenField(name, value) {
    const field = document.createElement("input")
    field.type = "hidden"
    field.name = name
    field.value = value
    return field
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
