// Load all Stimulus controllers from this directory.
// This file is auto-loaded by application.js.
import { Application } from "@hotwired/stimulus"
import TerminalController from "./terminal_controller"
import PollingController from "./polling_controller"
import ModalController from "./modal_controller"
import CodeMirrorController from "./codemirror_controller"

const application = Application.start()
application.register("terminal", TerminalController)
application.register("polling", PollingController)
application.register("modal", ModalController)
application.register("codemirror", CodeMirrorController)

export { application }
