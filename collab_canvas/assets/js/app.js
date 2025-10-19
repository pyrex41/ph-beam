

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
// Import PixiJS for WebGL rendering (using vendor bundle to avoid module resolution issues)
import * as PIXI from "../vendor/pixi.min.mjs"
// Import Canvas Manager hook
import CanvasManager from "./hooks/canvas_manager"
// Import Component Draggable hook
import ComponentDraggable from "./hooks/component_draggable"
// Import Color Picker hook
import { ColorPickerHook } from "./hooks/color_picker"
// Import Voice Input hook for AI commands
import VoiceInput from "./hooks/voice_input"
// Import AI Command Input hook for Enter key handling
import AICommandInput from "./hooks/ai_command_input"
// Import Layer Context Menu hook for layer panel right-click menu
import LayerContextMenu from "./hooks/layer_context_menu"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Custom logger to filter out noisy cursor_move events from all LiveView logs
const customLogger = (kind, msg, data) => {
  // Filter out cursor_move events from all log types
  const msgStr = typeof msg === 'string' ? msg : JSON.stringify(msg);
  if (msgStr.includes('cursor_move')) {
    return; // Silently ignore cursor_move logs
  }
  // Log everything else
  console.log(`[LiveView ${kind}]`, msg, data);
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  logger: customLogger,
  hooks: {
    CanvasRenderer: CanvasManager,
    ComponentDraggable: ComponentDraggable,
    ColorPicker: ColorPickerHook,
    VoiceInput: VoiceInput,
    AICommandInput: AICommandInput,
    LayerContextMenu: LayerContextMenu
  },
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// Disable debug mode to prevent cursor_move spam
liveSocket.disableDebug()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()  // Note: This will include cursor_move logs
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Expose PIXI globally for LiveView hooks
window.PIXI = PIXI

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    // reloader.enableServerLogs()  // Disabled to reduce console noise

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

