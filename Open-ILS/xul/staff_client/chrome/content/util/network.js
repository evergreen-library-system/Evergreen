dump('entering util/network.js\n');

if (typeof util == 'undefined') util = {};
util.network = function () {

	JSAN.use('util.error'); this.error = new util.error();

	return this;
};

util.network.prototype = {

	'link_id' : 0,

	'simple_request' : function(id,params,f,o_params) {
		return this.request(api[id].app,api[id].method,params,f,o_params);
	},

	'request' : function (app,name,params,f,o_params) {
		var request =  this._request(app,name,params,f,o_params);
		if (request) {
			return request.getResultObject();
		} else {
			return null;
		}
	},

	'_request' : function (app,name,params,f,o_params) {
		var obj = this;
		try {
			var sparams = js2JSON(params);
			obj.error.sdump('D_SES','request '+app+' '+name+' '+obj.error.pretty_print(sparams.slice(1,sparams.length-1))+
				'\no_params = ' + o_params + 
				'\nResult #' + (++obj.link_id) + ( f ? ' asynced' : ' synced' ) );
			var request = new RemoteRequest( app, name );
			for(var index in params) {
				request.addParam(params[index]);
			}
	
			if (f)  {
				request.setCompleteCallback(
					function(req) {
						try {
							var json_string = js2JSON(req.getResultObject());
							obj.error.sdump('D_SES_RESULT','asynced result #' 
								+ obj.link_id + '\n\n' 
								+ (json_string.length > 80 ? obj.error.pretty_print(json_string) : json_string) );
							req = obj.rerequest_on_session_timeout(app,name,params,req,o_params);
							req = obj.rerequest_on_perm_failure(app,name,params,req,o_params);
							if (o_params) {
								req = obj.rerequest_on_override(app,name,params,req,o_params);
							}
							req = obj.check_for_offline(app,name,params,req,o_params);
							f(req);
						} catch(E) {
							try {
								E.ilsevent = -2;
								E.textcode = 'Server/Method Error';
							} catch(F) {}
							f( { 'getResultObject' : function() { return E; } } );
						}
					}
				);
				request.send(false);
				return null;
			} else {
				request.send(true);
				var result = request.getResultObject();
				var json_string = js2JSON(result);
				this.error.sdump('D_SES_RESULT','synced result #' + obj.link_id + '\n\n' + ( json_string.length > 80 ? obj.error.pretty_print(json_string) : json_string ) );
				request = obj.rerequest_on_session_timeout(app,name,params,request,o_params);
				request = obj.rerequest_on_perm_failure(app,name,params,request,o_params);
				if (o_params) {
					request = obj.rerequest_on_override(app,name,params,request,o_params);
				}
				request = obj.check_for_offline(app,name,params,request,o_params);
				return request;
			}

		} catch(E) {
			if (instanceOf(E,perm_ex)) {
				alert('in util.network, _request : permission exception: ' + js2JSON(E));
			}
			throw(E);
		}
	},

	'check_for_offline' : function (app,name,params,req,o_params) {
		var obj = this;
		var result = req.getResultObject();
		if (result != null) return req;

		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
		var proceed = true;

		while(proceed) {

			proceed = false;

			var r;

			if (data.proceed_offline) {

				r = 1;

			} else {
				r = obj.error.yns_alert('Network failure.  Please check your Internet connection to ' + data.server_unadorned + ' and choose Retry Network.  If you need to enter Offline Mode, choose Proceed Offline in this and subsequent dialogs.  If you believe this error is due to a bug in Evergreen and not network problems, please contact your helpdesk or friendly Evergreen admins, and give them this message: method=' + name + ' params=' + js2JSON(params) + '.','Network Failure','Retry Network','Proceed Offline',null,'Check here to confirm this message');
				if (r == 1) {
					data.proceed_offline = true; data.stash('proceed_offline');
					dump('Remembering proceed_offline for 200000 ms.\n');
					setTimeout(
						function() {
							data.proceed_offline = false; data.stash('proceed_offline');
							dump('Setting proceed_offline back to false.\n');
						}, 200000
					);
				}
			}

			dump( r == 0 ? 'Retry Network\n' : 'Proceed Offline\n' );

			switch(r) {
				case 0: 
					req = obj._request(app,name,params,null,o_params);
					if (req.getResultObject() == null) proceed = true;
					return req;
				break;
				case 1: 
					return { 'getResultObject' : function() { return { 'ilsevent' : -1, 'textcode' : 'Network/Server Problem' }; } };
				break;
			}
		}
	},

	'rerequest_on_session_timeout' : function(app,name,params,req,o_params) {
		try {
			var obj = this;
			var robj = req.getResultObject();
			if (robj != null && robj.ilsevent && robj.ilsevent == 1001) {
				netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
				window.open(
					urls.XUL_AUTH_SIMPLE
					+ '?login_type=staff'
					+ '&desc_brief=' + window.escape('Your session has expired')
					+ '&desc_full=' + window.escape('Please re-login.  If after you have re-authenticated, you still see session expired dialogs like this one, please note where they are occuring and inform your friendly Evergreen developers of this debug information: ' + name),
					'simple_auth' + (new Date()).toString(),
					'chrome,resizable,modal,width=700,height=500'
				);
				JSAN.use('OpenILS.data');
				var data = new OpenILS.data(); data.init({'via':'stash'});
				if (data.temporary_session != '') {
					data.session.key = data.temporary_session.key; 
					data.session.authtime = data.temporary_session.authtime; 
					data.stash('session');
					params[0] = data.session.key;
					req = obj._request(app,name,params,null,o_params);
				}
			}
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
		return req;
	},
	
	'rerequest_on_perm_failure' : function(app,name,params,req,o_params) {
		try {
			var obj = this;
			var robj = req.getResultObject();
			if (robj != null && robj.ilsevent && robj.ilsevent == 5000) {
				netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
				window.open(
					urls.XUL_AUTH_SIMPLE
					+ '?login_type=temp'
					+ '&desc_brief=' + window.escape('Permission Denied: ' + robj.ilsperm)
					+ '&desc_full=' + window.escape('Another staff member with the above permission may authorize this specific action.  Please notify your library administrator if you need this permission.  If you feel you have received this exception in error, inform your friendly Evergreen developers of the above permission and this debug information: ' + name),
					'simple_auth' + (new Date()).toString(),
					'chrome,resizable,modal,width=700,height=500'
				);
				JSAN.use('OpenILS.data');
				var data = new OpenILS.data(); data.init({'via':'stash'});
				if (data.temporary_session != '') {
					params[0] = data.temporary_session.key;
					req = obj._request(app,name,params,null,o_params);
				}
			}
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
		return req;
	},

	'rerequest_on_override' : function (app,name,params,req,o_params) {
		var obj = this;
		try {
			if (!o_params.text) o_params.text = {};
			function override(r) {
				try {
					netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
					var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul">' + 
						'<groupbox><caption label="Exceptions"/>' + 
						'<grid><columns><column/><column/></columns><rows>';
					for (var i = 0; i < r.length; i++) {
						xml += '<row>' + 
							'<description style="color: red" tooltiptext="' + r[i].ilsevent + '">' + r[i].textcode + '</description>' + 
							'<description>' + (o_params.text[r[i].ilsevent] ? o_params.text[r[i].ilsevent](r[i]) : '') + '</description>' + 
							'</row><row>' + '<description>' + r[i].desc + '</description>' + '</row>';
					}
					xml += '</rows></grid></groupbox><groupbox><caption label="Override"/><hbox>' + 
						'<description>Force this action?</description>' + 
						'<button accesskey="N" label="No" name="fancy_cancel"/>' + 
						'<button id="override" accesskey="Y" label="Yes" name="fancy_submit" value="override"/></hbox></groupbox></vbox>';
					window.open(
						urls.XUL_FANCY_PROMPT
						+ '?xml=' + window.escape(xml)
						+ '&title=' + window.escape(o_params.title),
						'fancy_prompt', 'chrome,resizable,modal,width=700,height=500'
					);
					JSAN.use('OpenILS.data');
					var data = new OpenILS.data(); data.init({'via':'stash'});
					if (data.fancy_prompt_data != '') {
						req = obj._request(app,name + '.override',params);
					}
					return req;
				} catch(E) {
					alert('in util.network, rerequest_on_override, override:' + E);
				}
			}

			var result = req.getResultObject();
			if (!result) return req;

			if ( (typeof result.ilsevent != 'undefined') && (o_params.overridable_events.indexOf(result.ilsevent) != -1) ) {
				req = override([result]);
			} else {
				var found_good = false; var found_bad = false;
				for (var i = 0; i < result.length; i++) {
					if ( (result[i].ilsevent != 'undefined') && (o_params.overridable_events.indexOf(result[i].ilsevent) != -1) ) {
						found_good = true;
					} else {
						found_bad = true;
					}
				}
				if (found_good && (!found_bad)) req = override(result);
			}

			return req;
		} catch(E) {
			throw(E);
		}
	},


}

/*
function sample_callback(request) {
	var result = request.getResultObject();
}
*/

dump('exiting util/network.js\n');
