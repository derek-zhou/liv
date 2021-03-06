import "phoenix_html"
import {Socket} from "phoenix/assets/js/phoenix.js"
import {LiveSocket} from "phoenix_live_view/assets/js/phoenix_live_view.js"
import {toByteArray, fromByteArray} from "base64-js"

let xDown = null;
let yDown = null;
let messageHook = null;
let writeHook = null;
let attachments = [];
let blobURLs = [];
let uploads = [];
const chunkSize = 65536;

function browseTouchStart(evt) {
    xDown = evt.touches[0].clientX;
    yDown = evt.touches[0].clientY;
}

function browseTouchMove(evt) {
    if ( ! xDown || ! yDown ) {
        return;
    }
    var xUp = evt.touches[0].clientX;
    var yUp = evt.touches[0].clientY;
    var xDiff = xDown - xUp;
    var yDiff = yDown - yUp;

    /*most significant*/
    if ( Math.abs( xDiff ) > Math.abs( yDiff ) ) {
	if ( xDiff > 0 ) {
	    /* left swipe */
	    messageHook.pushEvent("forward_message", null);
	} else {
	    /* right swipe */
	    messageHook.pushEvent("backward_message", null);
	}
    }
    /* reset values */
    xDown = null;
    yDown = null;
}

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
	ret[key] = value;
    }
    return ret;
}

function push_attachment_chunk(first, chunk) {
    let binary = toByteArray(chunk);
    if (first) {
	attachments.push([binary]);
    } else {
	let last = attachments.pop();
	last.push(binary);
	attachments.push(last);
    }
}

function last_attachment_url() {
    return URL.createObjectURL(new Blob(attachments[attachments.length - 1]));
}

function add_attachment(event) {
    for (let i = 0; i < event.target.files.length; i++) {
	let file = event.target.files[i];
	let reader = new FileReader();
	reader.readAsArrayBuffer(file);
	reader.addEventListener("load", () => {
	    uploads.push(reader.result);
	    writeHook.pushEvent("write_attach", {name: file.name, size: file.size});
	});
    }
}

function upload_attachment(name, offset) {
    let data = uploads[0];
    let dlen = data.byteLength;
    let slen = dlen > offset + chunkSize ? chunkSize : dlen - offset;
    let slice = new Uint8Array(data, offset, slen);
    let chunk = fromByteArray(slice);
    writeHook.pushEvent("attachment_chunk", {chunk: chunk});
    if (offset + chunkSize >= dlen)
	uploads.shift();
}

let Hooks = new Object();

Hooks.Main = {
    mounted() {
	this.pushEvent("get_value", local_state());
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
    },
    reconnected() {
	this.pushEvent("get_value", local_state());
    }
};

Hooks.View = {
    mounted() {
	messageHook = this;
	this.el.addEventListener("touchstart", browseTouchStart);
	this.el.addEventListener("touchmove", browseTouchMove);
	this.handleEvent("chear_attachments", () => {
	    for (let url of blobURLs.values()) {
		URL.revokeObjectURL(url);
	    }
	    blobURLs = [];
	    attachments = [];
	});
	this.handleEvent("attachment_chunk", ({first, last, chunk}) => {
	    push_attachment_chunk(first, chunk);
	    if (last) {
		let url = last_attachment_url();
		blobURLs.push(url);
		this.pushEvent("ack_attachment_chunk", {url: url});
	    } else {
		this.pushEvent("ack_attachment_chunk", {});
	    }
	});
    }
};

Hooks.Attach = {
    mounted() {
	writeHook = this;
	this.el.querySelector("input#write-attach").addEventListener("change",
								     add_attachment);
	this.handleEvent("read_attachment", ({name, offset}) => {
	    upload_attachment(name, offset);
	});
    }
};


// Show progress bar on live navigation and form submits
window.addEventListener("phx:page-loading-start", info => show_progress_bar())
window.addEventListener("phx:page-loading-stop", info => hide_progress_bar())

document.addEventListener("DOMContentLoaded", () => {
    let appRoot = document.querySelector("body").getAttribute("data-app-root");
    let liveSocket = new LiveSocket(appRoot + "live", Socket, {hooks: Hooks});
    // connect if there are any LiveViews on the page
    liveSocket.connect();

    // expose liveSocket on window for web console debug logs and latency simulation:
    // >> liveSocket.enableDebug()
    // >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
    // >> liveSocket.disableLatencySim()
    window.liveSocket = liveSocket
});
