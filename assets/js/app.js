// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

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
import {hooks as colocatedHooks} from "phoenix-colocated/sahla"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const Hooks = {
  ...colocatedHooks,

  // Plate mask: formats Moroccan licence plates as 12345-A-67.
  PlateMask: {
    mounted() {
      this.el.addEventListener("input", (e) => {
        let v = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, "")
        if (v.length > 5) v = v.slice(0, 5) + "-" + v.slice(5)
        if (v.length > 7) v = v.slice(0, 7) + "-" + v.slice(7, 9)
        e.target.value = v
      })
    }
  },

  // OTP auto-advance: focus the next 4-digit box when a digit is entered.
  OtpAutoAdvance: {
    mounted() {
      const inputs = Array.from(this.el.querySelectorAll("input[data-otp-index]"))
      inputs.forEach((input, idx) => {
        input.addEventListener("input", (e) => {
          const val = e.target.value.replace(/\D/g, "")
          e.target.value = val.slice(0, 1)
          if (val && inputs[idx + 1]) inputs[idx + 1].focus()
          this.pushOtp(inputs)
        })
        input.addEventListener("keydown", (e) => {
          if (e.key === "Backspace" && !e.target.value && inputs[idx - 1]) {
            inputs[idx - 1].focus()
          }
        })
      })
    },

    pushOtp(inputs) {
      const code = inputs.map(i => i.value).join("")
      if (code.length === 6) {
        this.pushEventTo(this.el, "verify_otp", {code})
      }
    }
  },

  // Cloudflare Turnstile: render the widget into the hooked div and push the
  // verification token to the server on success. The site key is read from the
  // element's data-sitekey attribute (rendered from runtime config).
  Turnstile: {
    mounted() {
      this.render()
    },

    destroyed() {
      if (this._widgetId) {
        try { window.turnstile?.remove(this._widgetId) } catch (_) {}
        this._widgetId = null
      }
    },

    render() {
      const siteKey = this.el.dataset.sitekey
      if (!siteKey) return

      const renderWidget = () => {
        if (typeof window.turnstile !== "object" || !window.turnstile.render) return false
        this._widgetId = window.turnstile.render(this.el, {
          sitekey: siteKey,
          callback: (token) => this.pushEvent("set_turnstile_token", {token})
        })
        return true
      }

      if (renderWidget()) return

      // Cloudflare's explicit script; loaded once per page.
      if (!document.getElementById("cf-turnstile-script")) {
        const script = document.createElement("script")
        script.id = "cf-turnstile-script"
        script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
        script.async = true
        script.defer = true
        document.head.appendChild(script)
      }

      const tryRender = () => renderWidget() || (this._timer = setTimeout(tryRender, 200))
      tryRender()
    }
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Privacy-friendly Plausible goal events (§11, Appendix D). PII (phone, CIN,
// token, email) must NEVER be sent as props.
window.addEventListener("phx:plausible-goal", (e) => {
  const {name, props = {}} = e.detail || {}
  if (typeof window.plausible === "function" && name) {
    window.plausible("Goal", {name, props})
  }
})

window.addEventListener("phx:plausible-event", (e) => {
  const {name, props = {}} = e.detail || {}
  if (typeof window.plausible === "function" && name) {
    window.plausible(name, props)
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

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
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
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

