import {toByteArray} from "../../vendor/base64-js/index.js"
import * as Sanitizer from '../sanitizer.js';

export default {
    xDown: null,
    yDown: null,
    attachments: [],
    blobURLs: [],
    controller: null,
    textContainer: null,
    htmlContainer: null,
    
    mounted() {
	this.controller = new AbortController();
	this.el.addEventListener("touchstart", (e) => this.browseTouchStart(e.touches[0]));
	this.el.addEventListener("touchmove", (e) => this.browseTouchMove(e.touches[0]));
	document.addEventListener('keydown',
				  (e) => this.handleKeyDown(e.key),
				  {signal: this.controller.signal});

	Sanitizer.setup(this.el.querySelector(":scope > iframe#view-sanitizer"));
	let wrapper = this.el.querySelector(":scope > div#view-content");
	this.textContainer = wrapper.querySelector("pre");
	this.htmlContainer = wrapper.querySelector("div");

	this.handleEvent("clear_attachments", () => {
	    for (let url of this.blobURLs.values()) {
		URL.revokeObjectURL(url);
	    }
	    this.blobURLs = [];
	    this.attachments = [];
	    this.textContainer.innerText = "";
	    this.textContainer.removeAttribute("hidden");
	    this.htmlContainer.innerHTML = "";
	    this.htmlContainer.setAttribute("hidden", true);
	});

	this.handleEvent("attachment_start", ({type}) => {
	    this.attachments.push({type: type, content: []});
	});

	this.handleEvent("attachment_chunk", ({ref, chunk}) => {
	    if (this.attachments.length > 0) {
		let {type, content} = this.attachments.pop();
		if (type.substring(0, 5) == "text/")
		    content.push(chunk);
		else
		    content.push(toByteArray(chunk));
		this.attachments.push({type: type, content: content});
		this.pushEvent("ack_attachment_chunk", {ref})
	    }
	});

	this.handleEvent("attachment_end", ({ref, seq, name}) => {
	    if (this.attachments.length > 0) {
		let {type, content} = this.attachments[this.attachments.length - 1];

		if (name == "") {
		    // unnamed attachments are the mail text and mail html
		    switch (type) {
		    case "text/plain":
			this.textContainer.innerText = content.join("");
			break;
		    case "text/html":
			this.htmlContainer.innerHTML = Sanitizer.sanitizeHtml(content.join(""));
			this.textContainer.setAttribute("hidden", true);
			this.htmlContainer.removeAttribute("hidden");
			break;
		    }
		}

		let blob = new Blob(content, {type: type});
		let url = URL.createObjectURL(blob);
		this.blobURLs.push(url);
		this.pushEvent("update_attachment_url", {ref, seq, url});
	    }
	});
    },

    destroyed() {
	this.controller.abort();
    },
    
    handleKeyDown(key) {
	switch (key) {
	case 'n':
	case 'N':
	    if (this.el.offsetHeight > 0)
		this.pushEvent("forward_message", null);
	    break;
	case 'p':
	case 'P':
	    if (this.el.offsetHeight > 0)
		this.pushEvent("backward_message", null);
	    break;
	}
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
    }
};
