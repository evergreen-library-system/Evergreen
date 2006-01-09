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
								obj.controller.view.browser_browser.contentWindow.wrappedJSObject.print();
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
			obj.controller.view.browser_browser = document.getElementById('browser_browser');

			obj.buildProgressListener();
			dump('obj.controller.view.browser_browser.addProgressListener = ' 
				+ obj.controller.view.browser_browser.addProgressListener + '\n');
			obj.controller.view.browser_browser.addProgressListener(obj.progressListener,
			                Components.interfaces.nsIWebProgress.NOTIFY_ALL );

			obj.controller.view.browser_browser.setAttribute('src',obj.url);
			dump('url = ' + obj.url + '\n');

		} catch(E) {
			this.error.sdump('D_ERROR','util.browser.init: ' + E + '\n');
		}
	},

	'push_variables' : function() {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			/*
			var cw = this.controller.view.browser_browser.contentWindow.wrappedJSObject; 
			var cd = this.controller.view.browser_browser.contentDocument; 
			dump('contentWindow.wrappedJSObject = ' + cw + '\n');
			dump('contentWindow.wrappedJSObject.wrappedJSObject = ' + cw.wrappedJSObject + '\n');
			dump('contentDocument = ' + cd + '\n');
			dump('contentWindow.wrappedJSObject.document = ' + cw.document + '\n');
			dump('contentWindow.wrappedJSObject.document.ownerDocument = ' + cw.document.ownerDocument + '\n');
			dump('contentWindow.wrappedJSObject.document.parentNode = ' + cw.document.parentNode + '\n');
			*/
			this.controller.view.browser_browser.contentWindow.wrappedJSObject.IAMXUL = true;
			if (window.xulG) {
				this.controller.view.browser_browser.contentWindow.wrappedJSObject.xulG = window.xulG;
				dump('xulG = ' + js2JSON(xulG) + '\n');
				dump('xulG = ' + js2JSON(this.controller.view.browser_browser.contentWindow.wrappedJSObject.xulG) + '\n');
			}
		} catch(E) {
			this.error.sdump('D_ERROR','util.browser.push_variables: ' + E + '\n');
		}
	},

	'getWebNavigation' : function() {
		return document.getElementById('browser_browser').webNavigation;
	},

	'updateNavButtons' : function() {
		try {
			var n = obj.getWebNavigation();
			s += ('webNavigation = ' + n + '\n');
			s += ('webNavigation.canGoForward = ' + n.canGoForward + '\n');
			s += ('webNavigation.canGoBack = ' + n.canGoBack + '\n');
			if (n.canGoForward) {
				obj.controller.view.cmd_forward.disabled = false;
				obj.controller.view.cmd_forward.setAttribute('disabled','false');
			} else {
				obj.controller.view.cmd_forward.disabled = true;
				obj.controller.view.cmd_forward.setAttribute('disabled','true');
			}
			if (n.canGoBack) {
				obj.controller.view.cmd_back.disabled = false;
				obj.controller.view.cmd_back.setAttribute('disabled','false');
			} else {
				obj.controller.view.cmd_back.disabled = true;
				obj.controller.view.cmd_back.setAttribute('disabled','true');
			}
		} catch(E) {
			s += E;
		}
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
					netscape.security.PrivilegeManager.enablePrivilege( "UniversalXPConnect " );
					var s = '';
					const nsIWebProgressListener = Components.interfaces.nsIWebProgressListener;
					const nsIChannel = Components.interfaces.nsIChannel;
					//obj.push_variables(); obj.updateNavButtons();
					if (stateFlags == 65540 || stateFlags == 65537 || stateFlags == 65552) { return; }
					s = ('onStateChange: stateFlags = ' + stateFlags + ' status = ' + status + '\n');
					if (stateFlags & nsIWebProgressListener.STATE_IS_REQUEST) {
						s += ('\tSTATE_IS_REQUEST\n');
					}
					if (stateFlags & nsIWebProgressListener.STATE_IS_DOCUMENT) {
						s += ('\tSTATE_IS_DOCUMENT\n');
						if( stateFlags & nsIWebProgressListener.STATE_STOP ) {
							obj.push_variables(); obj.updateNavButtons();
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
