import { Controller } from "@hotwired/stimulus"

// Opens a <dialog> element by id. Useful for triggering modal opens from
// buttons without inline JS. The modal itself uses standard <dialog>
// + form/requestSubmit() so closing/cancelling works natively.
//
// Usage:
//   <button data-controller="modal" data-action="modal#open"
//           data-modal-id-value="create-vm-modal">Open</button>
export default class extends Controller {
  static values = { id: String }

  open() {
    const modal = document.getElementById(this.idValue || "create-vm-modal")
    if (modal && typeof modal.showModal === "function") modal.showModal()
  }

  close() {
    const modal = document.getElementById(this.idValue || "create-vm-modal")
    if (modal) modal.close()
  }
}
