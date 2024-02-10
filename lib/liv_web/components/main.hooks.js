export default {
    mounted() {
	this.handleEvent("set_value", ({key, value}) => {
	    let local_key = "liv_" + key;
	    if (value)
		localStorage.setItem(local_key, value);
	    else
		localStorage.removeItem(local_key);
	});
    }
};
