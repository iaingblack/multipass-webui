// Load all Stimulus controllers from this directory.
// This file is auto-loaded by application.js.
import { Application } from "@hotwired/stimulus"
import TerminalController from "./terminal_controller"
import PollingController from "./polling_controller"

const application = Application.start()
application.register("terminal", TerminalController)
application.register("polling", PollingController)

export { application }
