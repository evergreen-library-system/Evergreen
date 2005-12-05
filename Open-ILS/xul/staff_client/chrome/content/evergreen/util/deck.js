dump('entering util/deck.js\n');

if (typeof util == 'undefined') util = {};
util.deck = function (id) {

	this.node = document.getElementById(id);

	if (!this.node) throw('Could not find element ' + id);
	if (this.node.nodeName != 'deck') throw(id + ' is not a deck');

	return this;
};

util.deck.prototype = {

	'set_iframe' : function (url) {
		var idx = -1;
		var nodes = this.node.childNodes;
		for (var i in nodes) {
			if (nodes[i].getAttribute('src') == url) idx = i;
		}
		if (idx>-1) {
			this.node.selectedIndex = idx;
		} else {
			this.new_iframe(url);
		}
		
		
	},

	'reset_iframe' : function (url) {
		this.remove_iframe(url);
		this.new_iframe(url);
	},

	'new_iframe' : function (url) {
		var idx = -1;
		var nodes = this.node.childNodes;
		for (var i in nodes) {
			if (nodes[i].getAttribute('src' == url) idx = i;
		}
		if (idx>-1) throw('An iframe already exists in deck with url = ' + url);

		var iframe = document.createElement('iframe');
		iframe.setAttribute('src',url);
		iframe.setAttribute('flex','1');
		this.node.appendChild( iframe );
		//this.node.selectedIndex = this.node.childNodes.length - 1;
	}

	'remove_iframe' : function (url) {
		var idx = -1;
		var nodes = this.node.childNodes;
		for (var i in nodes) {
			if (nodes[i].getAttribute('src' == url) idx = i;
		}
		if (idx>-1) {
			this.node.removeChild( this.node.childNodes[ idx ] );
		}
	}
}	

dump('exiting util/deck.js\n');
