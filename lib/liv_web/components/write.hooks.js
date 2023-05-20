export default {
    mounted() {
	this.el
	    .querySelector('#text-box')
	    .addEventListener('input', (e) => this.autoResize(e.target));
    },

    autoResize(el) {
	let offset = el.offsetHeight - el.clientHeight;
	el.style.height = el.scrollHeight + offset + 'px';
    }
}
