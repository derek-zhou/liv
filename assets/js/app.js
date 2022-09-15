import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {toByteArray, fromByteArray} from "base64-js"

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

let Hooks = new Object();

Hooks.Main = {
    mounted() {
	this.handleEvent("get_value", ({key}) => {
	    let value = localStorage.getItem(key) || "";
	    let ret = new Object();
	    ret[key] = value;
	    this.pushEvent("get_value", ret);
	});
	this.handleEvent("set_value", ({key, value}) => {
	    let local_key = "liv_" + key;
	    if (value)
		localStorage.setItem(local_key, value);
	    else
		localStorage.removeItem(local_key);
	});
    }
};

Hooks.View = {
    xDown: null,
    yDown: null,
    attachments: [],
    blobURLs: [],
    
    mounted() {
	this.el.addEventListener("touchstart", (e) => this.browseTouchStart(e.touches[0]));
	this.el.addEventListener("touchmove", (e) => this.browseTouchMove(e.touches[0]));
	this.handleEvent("clear_attachments", () => {
	    for (let url of this.blobURLs.values()) {
		URL.revokeObjectURL(url);
	    }
	    this.blobURLs = [];
	    this.attachments = [];
	});
	this.handleEvent("attachment_chunk", ({first, last, chunk}) => {
	    this.push_attachment_chunk(first, chunk);
	    if (last) {
		let url = this.last_attachment_url();
		this.blobURLs.push(url);
		this.pushEvent("ack_attachment_chunk", {url: url});
	    } else {
		this.pushEvent("ack_attachment_chunk", {});
	    }
	});
    },
    
    browseTouchStart(dev) {
	this.xDown = dev.clientX;
	this.yDown = dev.clientY;
    },

    browseTouchMove(dev) {
	if ( ! this.xDown || ! this.yDown ) {
            return;
	}
	var xUp = dev.clientX;
	var yUp = dev.clientY;
	var xDiff = this.xDown - xUp;
	var yDiff = this.yDown - yUp;
	
	/*most significant*/
	if ( Math.abs( xDiff ) > Math.abs( yDiff ) ) {
	    if ( xDiff > 0 ) {
		/* left swipe */
		this.pushEvent("forward_message", null);
	    } else {
		/* right swipe */
		this.pushEvent("backward_message", null);
	    }
	}
	/* reset values */
	this.xDown = null;
	this.yDown = null;
    },

    push_attachment_chunk(first, chunk) {
	let binary = toByteArray(chunk);
	if (first) {
	    this.attachments.push([binary]);
	} else {
	    let last = this.attachments.pop();
	    last.push(binary);
	    this.attachments.push(last);
	}
    },
    
    last_attachment_url() {
	return URL.createObjectURL(new Blob(this.attachments[this.attachments.length - 1]));
    }
};

Hooks.Attach = {
    chunkSize: 16384,
    uploads: [],
    
    mounted() {
	this.el
	    .querySelector("input#write-attach")
	    .addEventListener("change", (e) => this.add_attachment(e.target.files));
	this.handleEvent("read_attachment", ({name, offset}) => {
	    this.upload_attachment(name, offset);
	});
    },

    async add_attachment(files) {
	for (let i = 0; i < files.length; i++) {
	    let file = files[i];
	    let buffer = await new Promise((resolve) => {
		const reader = new FileReader();
		reader.onload = (e) => resolve(e.target.result);
		reader.readAsArrayBuffer(file);
	    });
	    this.uploads.push(buffer);
	    this.pushEvent("write_attach", {name: file.name, size: file.size});
	}
    },
    
    upload_attachment(name, offset) {
	let data = this.uploads[0];
	let dlen = data.byteLength;
	let slen = dlen > offset + this.chunkSize ? this.chunkSize : dlen - offset;
	let slice = new Uint8Array(data, offset, slen);
	let chunk = fromByteArray(slice);
	this.pushEvent("attachment_chunk", {chunk: chunk});
	if (offset + this.chunkSize >= dlen)
	    this.uploads.shift();
    }
};


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
