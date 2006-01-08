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

			obj.session = params['session'];
			obj.url = params['url'];

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
								obj.controller.view.browser_browser.contentWindow.print();
							}
						],
						'cmd_forward' : [
							['command'],
							function() {
								var s = '';
								try {
									netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
									var n = obj.getWebNavigation();
									s += ('\nwebNavigation = ' + n + '\n');
									s += ('\nwebNavigation.canGoForward = ' + n.canGoForward + '\n');
									s += ('\nwebNavigation.canGoBack = ' + n.canGoBack + '\n');
									if (n.canGoForward) n.goForward();
								} catch(E) {
									var err = 'cmd_forward: ' + E;
									obj.error.sdump('D_ERROR',err);
								}
								dump(s);
							}
						],
						'cmd_back' : [
							['command'],
							function() {
								var s = '';
								try {
									netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
									var n = obj.getWebNavigation();
									s += ('\nwebNavigation = ' + n + '\n');
									s += ('\nwebNavigation.canGoForward = ' + n.canGoForward + '\n');
									s += ('\nwebNavigation.canGoBack = ' + n.canGoBack + '\n');
									if (n.canGoBack) n.goBack();
								} catch(E) {
									var err = 'cmd_back: ' + E;
									obj.error.sdump('D_ERROR',err);
								}
								dump(s);
							}
						],
					}
				}
			);
			obj.controller.view.browser_browser = document.getElementById('browser_browser');

			obj.buildProgressListener();
			dump('obj.controller.view.browser_browser.addProgressListener = ' 
				+ obj.controller.view.browser_browser.addProgressListener + '\n');
			obj.controller.view.browser_browser.addProgressListener(obj.progressListener,
			                Components.interfaces.nsIWebProgress.NOTIFY_ALL );

			obj.controller.view.browser_browser.setAttribute('src',obj.url);

		} catch(E) {
			this.error.sdump('D_ERROR','util.browser.init: ' + E + '\n');
		}
	},

	'push_variables' : function() {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			this.controller.view.browser_browser.contentWindow.IAMXUL = true;
			if (window.xulG) this.controller.view.browser_browser.contentWindow.xulG = xulG;
		} catch(E) {
			this.error.sdump('D_ERROR','util.browser.push_variables: ' + E + '\n');
		}
	},

	'getWebNavigation' : function() {
		return document.getElementById('browser_browser').webNavigation;
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
					netscape.security.PrivilegeManager.enablePrivilege(
						"UniversalXPConnect " 
						+ "UniversalPreferencesWrite "
						+ "UniversalBrowserWrite "
						+ "UniversalPreferencesRead "
						+ "UniversalBrowserRead"
					);
					var s = '';
					const nsIWebProgressListener = Components.interfaces.nsIWebProgressListener;
					const nsIChannel = Components.interfaces.nsIChannel;
					if (stateFlags == 65540 || stateFlags == 65537 || stateFlags == 65552) { return; }
					s = ('onStateChange: stateFlags = ' + stateFlags + ' status = ' + status + '\n');
					if (stateFlags & nsIWebProgressListener.STATE_IS_REQUEST) {
						s += ('\tSTATE_IS_REQUEST\n');
					}
					if (stateFlags & nsIWebProgressListener.STATE_IS_DOCUMENT) {
						s += ('\tSTATE_IS_DOCUMENT\n');
						if( stateFlags & nsIWebProgressListener.STATE_STOP ) {
							obj.push_variables(); 
							try {
								var n = obj.getWebNavigation();
								s += ('\nwebNavigation = ' + n + '\n');
								s += ('\nwebNavigation.canGoForward = ' + n.canGoForward + '\n');
								s += ('\nwebNavigation.canGoBack = ' + n.canGoBack + '\n');
								if (n.canGoForward) {
									obj.controller.view.cmd_forward.disabled = false;
								} else {
									obj.controller.view.cmd_forward.disabled = true;
								}
								if (n.canGoBack) {
									obj.controller.view.cmd_back.disabled = false;
								} else {
									obj.controller.view.cmd_back.disabled = true;
								}
							} catch(E) {
								s += E;
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
					obj.error.sdump('D_OPAC',s);	
				}
			}
			obj.progressListener.QueryInterface = function(){return this;};
		} catch(E) {
			this.error.sdump('D_ERROR','util.browser.buildProgressListener: ' + E + '\n');
		}
	},
}

dump('exiting util.browser.js\n');
