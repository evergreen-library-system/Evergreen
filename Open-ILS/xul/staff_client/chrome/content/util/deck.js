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
		var error = 'util.deck: ' + id + 'is not a deck' + "\nIt's a " + this.node.nodeName;
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
		this.error.sdump('D_TRACE','util.deck.set_iframe: url = ' + url);
		var idx = this.find_index(url);
		if (idx>-1) {
			this.node.selectedIndex = idx;

			var iframe = this.node.childNodes[idx];

			if (content_params) {
				try {
					netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
					this.error.sdump('D_DECK', 'set_iframe\nurl = ' + url + '\nframe.contentWindow = ' + iframe.contentWindow + '\n' + 'content_params = ' + js2JSON(content_params) );
					iframe.contentWindow.IAMXUL = true;
					iframe.contentWindow.xulG = content_params;
				} catch(E) {
					this.error.sdump('D_ERROR','E: ' + E + '\n');
				}
			}

			return iframe;
		} else {
			return this.new_iframe(url,params,content_params);
		}
		
	},

	'reset_iframe' : function (url,params,content_params) {
		this.remove_iframe(url);
		return this.new_iframe(url,params,content_params);
	},

	'new_iframe' : function (url,params,content_params) {
		var idx = this.find_index(url);
		if (idx>-1) throw('An iframe already exists in deck with url = ' + url);

		var iframe = document.createElement('iframe');
		iframe.setAttribute('src',url);
		//iframe.setAttribute('flex','1');
		//iframe.setAttribute('style','overflow: scroll');
		//iframe.setAttribute('style','border: solid thin red');
		this.node.appendChild( iframe );
		this.node.selectedIndex = this.node.childNodes.length - 1;
		if (content_params) {
			try {
				netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
				this.error.sdump('D_DECK', 'new_iframe\nurl = ' + url + '\nframe.contentWindow = ' + iframe.contentWindow + '\n' + 'content_params = ' + js2JSON(content_params) );
				iframe.contentWindow.IAMXUL = true;
				iframe.contentWindow.xulG = content_params;
				this.error.sdump('D_DECK', 'contentWindow.xulG = ' + js2JSON(iframe.contentWindow.xulG) );
			} catch(E) {
				this.error.sdump('D_ERROR','E: ' + E + '\n');
			}
		}
		return iframe;
	},

	'remove_iframe' : function (url) {
		var idx = this.find_index(url);
		if (idx>-1) {
			this.node.removeChild( this.node.childNodes[ idx ] );
		}
	},

	/* FIXME -- consider all the browser stuff broken.. very weird behavior in new_browser */

	'set_browser' : function (url,params,content_params) {
		this.error.sdump('D_TRACE','util.deck.set_browser: url = ' + url);
		var idx = this.find_index(url);
		if (idx>-1) {
			this.node.selectedIndex = idx;

			var browser = this.node.childNodes[idx];

			if (content_params) {
				/* FIXME -- we'd need to reach in and change the passthru_content_params for the browser, as well as the xulG for the content */ 
				alert("we're in set_browser, content_params = true");
			}

			return browser;
		} else {
			return this.new_browser(url,params,content_params);
		}
		
	},

	'reset_browser' : function (url,params,content_params) {
		this.remove_browser(url);
		return this.new_browser(url,params,content_params);
	},

	'new_browser' : function (url,params,content_params) {
		try {
		alert('in new_browser.. typeof xulG == ' + typeof xulG);
		alert('in new_browser.. typeof content_params == ' + typeof content_params);
		var obj = this;
		var idx = this.find_index(url);
		if (idx>-1) throw('A browser already exists in deck with url = ' + url);

		var browser = document.createElement('browser');
		obj.id_incr++;
		browser.setAttribute('type','content');
		browser.setAttribute('id','frame_'+obj.id_incr);
		browser.setAttribute('src',url);
		this.node.appendChild( browser );
		alert('after append');
		this.node.selectedIndex = this.node.childNodes.length - 1;
			dump('creating browser with src = ' + url + '\n');
			alert('content_params = ' + content_params);
			JSAN.use('util.browser');
			var b = new util.browser();
			b.init(
				{
					'url' : url,
					'push_xulG' : true,
					'alt_print' : false,
					'browser_id' : 'frame_'+obj.id_incr,
					'passthru_content_params' : content_params,
				}
			);
		return browser;
		} catch(E) {
			alert(E);
		}
	},

	'remove_browser' : function (url) {
		var idx = this.find_index(url);
		if (idx>-1) {
			this.node.removeChild( this.node.childNodes[ idx ] );
		}
	},

	'id_incr' : 0,
}	

dump('exiting util/deck.js\n');
