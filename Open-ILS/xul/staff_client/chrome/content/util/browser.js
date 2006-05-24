dump('entering util.browser.js\n');

if (typeof util == 'undefined') util = {};
util.browser = function (params) {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		JSAN.use('util.error'); this.error = new util.error();
	} catch(E) {
		dump('util.browser: ' + E + '\n');
	}
}

util.browser.prototype = {

	'init' : function( params ) {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

			var obj = this;

			obj.url = params['url'];
			obj.push_xulG = params['push_xulG'];
			obj.alt_print = params['alt_print'];
			obj.browser_id = params['browser_id'];
			obj.passthru_content_params = params['passthru_content_params'];
			obj.on_url_load = params['on_url_load'];

			JSAN.use('util.controller'); obj.controller = new util.controller();
			obj.controller.init(
				{
					control_map : {
						'cmd_broken' : [
							['command'],
							function() { alert('Not Yet Implemented'); }
						],
						'cmd_print' : [
							['command'],
							function() {
								netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
								if (obj.alt_print) {
									JSAN.use('util.print'); var p = new util.print();
									p.NSPrint(obj.get_content(),false,{});
								} else {
									obj.get_content().print();
								}
							}
						],
						'cmd_forward' : [
							['command'],
							function() {
								try {
									netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
									var n = obj.getWebNavigation();
									if (n.canGoForward) n.goForward();
								} catch(E) {
									var err = 'cmd_forward: ' + E;
									obj.error.sdump('D_ERROR',err);
								}
							}
						],
						'cmd_back' : [
							['command'],
							function() {
								try {
									netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
									var n = obj.getWebNavigation();
									if (n.canGoBack) n.goBack();
								} catch(E) {
									var err = 'cmd_back: ' + E;
									obj.error.sdump('D_ERROR',err);
								}
							}
						],
					}
				}
			);
			obj.controller.render();

			var browser_id = 'browser_browser'; if (obj.browser_id) browser_id = obj.browser_id;
			obj.controller.view.browser_browser = document.getElementById(browser_id);

			obj.buildProgressListener();
			dump('obj.controller.view.browser_browser.addProgressListener = ' 
				+ obj.controller.view.browser_browser.addProgressListener + '\n');
			obj.controller.view.browser_browser.addProgressListener(obj.progressListener,
			                Components.interfaces.nsIWebProgress.NOTIFY_ALL );

			obj.controller.view.browser_browser.setAttribute('src',obj.url);
			dump('browser url = ' + obj.url + '\n');

		} catch(E) {
			this.error.sdump('D_ERROR','util.browser.init: ' + E + '\n');
		}
	},

	'get_content' : function() {
		try {
			if (this.controller.view.browser_browser.contentWindow.wrappedJSObject) {
				return this.controller.view.browser_browser.contentWindow.wrappedJSObject;
			} else {
				return this.controller.view.browser_browser.contentWindow;
			}
		} catch(E) {
			alert('util.browser.get_content(): ' + E);
		}
	},

	'push_variables' : function() {
		try {
			var obj = this;
			if (!obj.push_xulG) return;
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			var cw = this.get_content();
			cw.IAMXUL = true;
			cw.xulG = obj.passthru_content_params;
			dump('xulG = ' + js2JSON(cw.xulG) + '\n');
		} catch(E) {
			this.error.sdump('D_ERROR','util.browser.push_variables: ' + E + '\n');
		}
	},

	'getWebNavigation' : function() {
		try {
			var wn = this.controller.view.browser_browser.webNavigation;
			dump('getWebNavigation() = ' + wn + '\n');
			return wn;
		} catch(E) {
			alert('util.browser.getWebNavigation(): ' + E );
		}
	},

	'updateNavButtons' : function() {
		var obj = this; var s = '';
		try {
			var n = obj.getWebNavigation();
			s += ('webNavigation = ' + n + '\n');
			s += ('webNavigation.canGoForward = ' + n.canGoForward + '\n');
			if (n.canGoForward) {
				if (typeof obj.controller.view.cmd_forward != 'undefined') {
					obj.controller.view.cmd_forward.disabled = false;
					obj.controller.view.cmd_forward.setAttribute('disabled','false');
				}
			} else {
				if (typeof obj.controller.view.cmd_forward != 'undefined') {
					obj.controller.view.cmd_forward.disabled = true;
					obj.controller.view.cmd_forward.setAttribute('disabled','true');
				}
			}
		} catch(E) {
			s += E + '\n';
		}
		try {
			var n = obj.getWebNavigation();
			s += ('webNavigation = ' + n + '\n');
			s += ('webNavigation.canGoBack = ' + n.canGoBack + '\n');
			if (n.canGoBack) {
				if (typeof obj.controller.view.cmd_back != 'undefined') {
					obj.controller.view.cmd_back.disabled = false;
					obj.controller.view.cmd_back.setAttribute('disabled','false');
				}
			} else {
				if (typeof obj.controller.view.cmd_back != 'undefined') {
					obj.controller.view.cmd_back.disabled = true;
					obj.controller.view.cmd_back.setAttribute('disabled','true');
				}
			}
		} catch(E) {
			s += E + '\n';
		}

		dump(s);
	},

	'buildProgressListener' : function() {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

			var obj = this;
			obj.progressListener = {
				onProgressChange	: function(){},
				onLocationChange	: function(){},
				onStatusChange		: function(){},
				onSecurityChange	: function(){},
				onStateChange 		: function ( webProgress, request, stateFlags, status) {
					try {
						netscape.security.PrivilegeManager.enablePrivilege( "UniversalXPConnect" );
						var s = obj.url + '\n' + obj.get_content().location.href + '\n';
						const nsIWebProgressListener = Components.interfaces.nsIWebProgressListener;
						const nsIChannel = Components.interfaces.nsIChannel;
						if (stateFlags == 65540 || stateFlags == 65537 || stateFlags == 65552) { return; }
						s += ('onStateChange: stateFlags = ' + stateFlags + ' status = ' + status + '\n');
						if (stateFlags & nsIWebProgressListener.STATE_IS_REQUEST) {
							s += ('\tSTATE_IS_REQUEST\n');
						}
						if (stateFlags & nsIWebProgressListener.STATE_IS_DOCUMENT) {
							s += ('\tSTATE_IS_DOCUMENT\n');
							if( stateFlags & nsIWebProgressListener.STATE_STOP ) {
								obj.push_variables(); obj.updateNavButtons();
								if (typeof obj.on_url_load == 'function') {
									try {
										obj.error.sdump('D_TRACE','calling on_url_load');
										obj.on_url_load( obj.controller.view.browser_browser );
									} catch(E) {
										obj.error.sdump('D_ERROR','on_url_load: ' + E );
									}
								}
							}
						}
						if (stateFlags & nsIWebProgressListener.STATE_IS_NETWORK) {
							s += ('\tSTATE_IS_NETWORK\n');
						}
						if (stateFlags & nsIWebProgressListener.STATE_IS_WINDOW) {
							s += ('\tSTATE_IS_WINDOW\n');
						}
						if (stateFlags & nsIWebProgressListener.STATE_START) {
							s += ('\tSTATE_START\n');
						}
						if (stateFlags & nsIWebProgressListener.STATE_REDIRECTING) {
							s += ('\tSTATE_REDIRECTING\n');
						}
						if (stateFlags & nsIWebProgressListener.STATE_TRANSFERING) {
							s += ('\tSTATE_TRANSFERING\n');
						}
						if (stateFlags & nsIWebProgressListener.STATE_NEGOTIATING) {
							s += ('\tSTATE_NEGOTIATING\n');
						}
						if (stateFlags & nsIWebProgressListener.STATE_STOP) {
							s += ('\tSTATE_STOP\n');
						}
						obj.error.sdump('D_BROWSER',s);	
					} catch(E) {
						alert('util.browser.progresslistener.onstatechange: ' + js2JSON(E));
					}
				}
			}
			obj.progressListener.QueryInterface = function(){return this;};
		} catch(E) {
			this.error.sdump('D_ERROR','util.browser.buildProgressListener: ' + E + '\n');
		}
	},
}

dump('exiting util.browser.js\n');
