import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toast"]
  static values = { 
    autoDismiss: { type: Boolean, default: true },
    dismissDelay: { type: Number, default: 15000 }
  }

  connect() {
    if (this.autoDismissValue) {
      this.startAutoDismiss()
    }
  }

  startAutoDismiss() {
    setTimeout(() => {
      this.dismiss()
    }, this.dismissDelayValue)
  }

  dismiss() {
    this.element.classList.add('opacity-0', 'transform', 'scale-95')
    setTimeout(() => {
      this.element.remove()
    }, 150)
  }
} 