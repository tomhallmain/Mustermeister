import { Controller } from "@hotwired/stimulus"

// Native `confirm()` dialogs can't show task-specific details (which task,
// how many comments will be cascade-deleted with it), so a custom modal is
// used instead. The delete button's own form is stashed on open and only
// submitted if the user confirms - clicking cancel (or dismissing) simply
// discards it, leaving the task untouched.
export default class extends Controller {
  static targets = ["modal", "body", "commentsWarning", "confirmButton"]

  connect() {
    this.formToSubmit = null
  }

  open(event) {
    event.preventDefault()

    this.formToSubmit = event.currentTarget.closest("form")
    this.bodyTarget.textContent = event.params.body

    if (event.params.commentsWarning) {
      this.commentsWarningTarget.textContent = event.params.commentsWarning
      this.commentsWarningTarget.classList.remove("hidden")
    } else {
      this.commentsWarningTarget.textContent = ""
      this.commentsWarningTarget.classList.add("hidden")
    }

    this.modalTarget.classList.remove("hidden")
  }

  cancel() {
    this.modalTarget.classList.add("hidden")
    this.formToSubmit = null
  }

  confirm() {
    if (!this.formToSubmit) return

    this.confirmButtonTarget.disabled = true
    this.formToSubmit.requestSubmit()
  }
}
