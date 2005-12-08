dump('entering util/deck.js\n');

if (typeof util == 'undefined') util = {};
util.deck = function (id) {

	this.node = document.getElementById(id);

	JSAN.use('util.error'); this.error = new util.error();

	if (!this.node) {
		var error = 'util.deck: Could not find element ' + id;
		this.error.sdump('D_ERROR',error);
		throw(error);
	}
	if (this.node.nodeName != 'deck') {
		var error = 'util.deck: ' + id + 'is not a deck';
		this.error.sdump('D_ERROR',error);
		throw(error);
	}

	return this;
};

util.deck.prototype = {

	'find_index' : function (url) {
		var idx = -1;
		var nodes = this.node.childNodes;
		for (var i = 0; i < nodes.length; i++) {
			if (nodes[i].getAttribute('src') == url) idx = i;
		}
		return idx;
	},

	'set_iframe' : function (url,params,content_params) {
		var idx = this.find_index(url);
		if (idx>-1) {
			this.node.selectedIndex = idx;
		} else {
			this.new_iframe(url,params,content_params);
		}
		
		
	},

	'reset_iframe' : function (url,params,content_params) {
		this.remove_iframe(url);
		this.new_iframe(url,params,content_params);
	},

	'new_iframe' : function (url,params,content_params) {
		var idx = this.find_index(url);
		if (idx>-1) throw('An iframe already exists in deck with url = ' + url);

		var iframe = document.createElement('iframe');
		iframe.setAttribute('src',url);
		iframe.setAttribute('flex','1');
		this.node.appendChild( iframe );
		this.node.selectedIndex = this.node.childNodes.length - 1;
		if (content_params) {
			try {
				netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
				this.error.sdump('D_DECK', 'frame.contentWindow = ' + frame.contentWindow + '\n');
				iframe.contentWindow.IAMXUL = true;
				iframe.contentWindow.xulG = content_params;
			} catch(E) {
				dump('E: ' + E + '\n');
			}
			alert('new_iframe: got here3');
		}
	},

	'remove_iframe' : function (url) {
		var idx = this.find_index(url);
		if (idx>-1) {
			this.node.removeChild( this.node.childNodes[ idx ] );
		}
	}
}	

dump('exiting util/deck.js\n');
