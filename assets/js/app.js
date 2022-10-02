import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import Hooks from "./_hooks";

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

function local_state() {
    let ret = new Object();
    ret.timezoneOffset = new Date().getTimezoneOffset();
    ret.language = navigator.language;
    // dump everthing from localStorage to the server side
    for (let i = 0; i < localStorage.length; i++) {
	let key = localStorage.key(i);
	let value = localStorage.getItem(key);
	let found = key.match(/^liv_(.*)/);
	if (found)
	    ret[found[1]] = value;
    }
    return ret;
}

// Show progress bar on live navigation and form submits
window.addEventListener("phx:page-loading-start", info => show_progress_bar())
window.addEventListener("phx:page-loading-stop", info => hide_progress_bar())

document.addEventListener("DOMContentLoaded", () => {
    let appRoot = document.querySelector("body").getAttribute("data-app-root");
    let liveSocket = new LiveSocket(appRoot + "live", Socket,
				    {hooks: Hooks, params: local_state});
    // connect if there are any LiveViews on the page
    liveSocket.connect();

    // expose liveSocket on window for web console debug logs and latency simulation:
    // >> liveSocket.enableDebug()
    // >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
    // >> liveSocket.disableLatencySim()
    window.liveSocket = liveSocket
});
