export default {
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
