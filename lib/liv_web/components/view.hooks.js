import {toByteArray} from "../../vendor/base64-js/index.js"

export default {
    xDown: null,
    yDown: null,
    attachments: [],
    blobURLs: [],
    controller: null,
    
    mounted() {
	this.controller = new AbortController();
	this.el.addEventListener("touchstart", (e) => this.browseTouchStart(e.touches[0]));
	this.el.addEventListener("touchmove", (e) => this.browseTouchMove(e.touches[0]));
	document.addEventListener('keydown',
				  (e) => this.handleKeyDown(e.key),
				  {signal: this.controller.signal});
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
