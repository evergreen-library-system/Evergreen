function ProgressBar(size,interval) {

	if(interval == null) interval = 100;
	if(size == null) size = 10;
	this.is_running = false;

	this.size = size;
	this.interval = interval;

	this.div = createAppElement("div");
	this.div.className = "progress_bar";
	this.current	= 0;
	this.timeoutId;

	this.percentDiv = createAppElement("div");
	add_css_class(this.percentDiv, "progress_percent");

	var divWidth = parseInt(100 / parseInt(size));
	for( i = 0; i!= size; i++ ) {
		var div = createAppElement("div");
		div.className = "progress_bar_chunk";
		div.style.width = "" + divWidth + "%";
		this.div.appendChild(div);
	}
}

ProgressBar.prototype.running = function() {
	return this.is_running;
}

ProgressBar.prototype.getNode = function() {
	return this.div;
}

ProgressBar.prototype.next = function() {
	this.manualNext();
	var obj = this;
	this.timeoutId = setTimeout( function(){ obj.next(); }, this.interval );
}

ProgressBar.prototype.start = function() {
	this.is_running = true;
	this.next();
}

ProgressBar.prototype.stop = function() {
	this.is_running = false;
	this.current = this.size;
	clearTimeout(this.timeoutId);
	/*
	for(var i in this.div.childNodes) {
		this.div.childNodes[i].className = "progress_bar_chunk_active";
	}
	*/
	add_css_class(this.percentDiv, "hide_me");
	add_css_class(this.div, "progress_bar_done");
	this.percentDiv.innerHTML = "";
}


	
ProgressBar.prototype.manualNext = function() {
	if( this.current == this.size ) {
		for( var i in this.div.childNodes ) {
			if(!this.div.childNodes[i])
			this.div.childNodes[i].className = "progress_bar_chunk";
		}
		this.current = 0;
	} else {
		var node = this.div.childNodes[this.current];
		node.className = "progress_bar_chunk_active";
		this.current = parseInt(this.current) + 1;
	}

	this.percentDiv.innerHTML = parseInt((parseInt(this.current) / parseInt(this.size) * 100)) + "%";
}
