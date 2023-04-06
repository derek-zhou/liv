import {fromByteArray} from "../../vendor/base64-js/index.js"

export default {
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
