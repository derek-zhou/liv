import "./phoenix_html.js"
import {Socket} from "./phoenix.js"
import {LiveSocket} from "./phoenix_live_view.js"

function show_progress_bar() {
    var bar = document.querySelector("div#app-progress-bar");
    bar.style.width = "100%";
    bar.style.opacity = "1";
}

function hide_progress_bar() {
    var bar = document.querySelector("div#app-progress-bar");
    bar.style.width = "0%";
    bar.style.opacity = "0";
}

let Hooks = new Object();
Hooks.Main = {
    mounted() {
	// dump everthing from localStorage to the server side
	let ret = new Object();
	ret.timezoneOffset = new Date().getTimezoneOffset();
	for (let i = 0; i < localStorage.length; i++) {
	    let key = localStorage.key(i);
	    let value = localStorage.getItem(key);
	    ret[key] = value;
	}
	this.pushEvent("get_value", ret);
	this.handleEvent("get_value", ({key}) => {
	    let value = localStorage.getItem(key) || "";
	    let ret = new Object();
	    ret[key] = value;
	    this.pushEvent("get_value", ret);
	});
	this.handleEvent("set_value", ({key, value}) => {
	    if (value)
		localStorage.setItem(key, value);
	    else
		localStorage.removeItem(key);
	});
    }
};
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: Hooks})

// Show progress bar on live navigation and form submits
window.addEventListener("phx:page-loading-start", info => show_progress_bar())
window.addEventListener("phx:page-loading-stop", info => hide_progress_bar())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

