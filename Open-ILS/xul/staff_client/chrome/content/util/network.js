dump('entering util/network.js\n');

if (typeof util == 'undefined') util = {};
util.network = function () {

	JSAN.use('util.error'); this.error = new util.error();
	// Place a test here for network connectivity
	// this.offline = true;

	return this;
};

util.network.prototype = {

	// Flag for whether the staff client should act as if it were offline or not
	'offline' : false,

	'link_id' : 0,

	'simple_request' : function(id,params,f) {
		return this.request(api[id].app,api[id].method,params,f);
	},

	'request' : function (app,name,params,f) {
		var request =  this.bare_request(app,name,params,f);
		if (request) {
			return request.getResultObject();
		} else {
			return null;
		}
	},

	'bare_request' : function (app,name,params,f) {
		var obj = this;
		try {
			var sparams = js2JSON(params);
			obj.error.sdump('D_SES','request '+app+' '+name+' '+sparams.slice(1,sparams.length-1)+
				'\nResult #' + (++obj.link_id) + ( f ? ' asynced' : ' synced' ) );
			var request = new RemoteRequest( app, name );
			for(var index in params) {
				request.addParam(params[index]);
			}
	
			if (f)  {
				request.setCompleteCallback(
					function(req) {
						try {
							obj.error.sdump('D_SES_RESULT','asynced result #' 
								+ obj.link_id + '\n\n' 
								+ js2JSON(req.getResultObject()));
							req = obj.rerequest_on_session_timeout(app,name,params,req);
							req = obj.rerequest_on_perm_failure(app,name,params,req);
							f(req);
						} catch(E) {
							alert(E);
						}
					}
				);
				request.send(false);
				return null;
			} else {
				request.send(true);
				request = obj.rerequest_on_session_timeout(app,name,params,request);
				request = obj.rerequest_on_perm_failure(app,name,params,request);
				var result = request.getResultObject();
				this.error.sdump('D_SES_RESULT','synced result #' + obj.link_id + '\n\n' + js2JSON(result));
				return request;
			}

		} catch(E) {
			if (instanceOf(E,perm_ex)) {
				alert('permission exception: ' + js2JSON(E));
			}
			throw(E);
		}
	},

	'rerequest_on_session_timeout' : function(app,name,params,req) {
		try {
			var obj = this;
			var robj = req.getResultObject();
			if (robj.ilsevent && robj.ilsevent == 1001) {
				netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
				window.open(
					urls.XUL_AUTH_SIMPLE
					+ '?login_type=staff'
					+ '&desc_brief=' + window.escape('Your session has expired')
					+ '&desc_full=' + window.escape('Please re-login.  If after you have re-authenticated, you still see session expired dialogs like this one, please note where they are occuring and inform your friendly Evergreen developers of this debug information: ' + name),
					'simple_auth',
					'chrome,resizable,modal,width=700,height=500'
				);
				JSAN.use('OpenILS.data');
				var data = new OpenILS.data(); data.init({'via':'stash'});
				if (data.temporary_session != '') {
					data.session = data.temporary_session; data.stash('session');
					params[0] = data.session;
					req = obj.bare_request(app,name,params);
				}
			}
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
		return req;
	},
	
	'rerequest_on_perm_failure' : function(app,name,params,req) {
		try {
			var obj = this;
			var robj = req.getResultObject();
			if (robj.ilsevent && robj.ilsevent == 5000) {
				netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
				window.open(
					urls.XUL_AUTH_SIMPLE
					+ '?login_type=temp'
					+ '&desc_brief=' + window.escape('Permission Denied: ' + robj.ilsperm)
					+ '&desc_full=' + window.escape('Another staff member with the above permission may authorize this specific action.  Please notify your library administrator if you need this permission.  If you feel you have received this exception in error, inform your friendly Evergreen developers of the above permission and this debug information: ' + name),
					'simple_auth',
					'chrome,resizable,modal,width=700,height=500'
				);
				JSAN.use('OpenILS.data');
				var data = new OpenILS.data(); data.init({'via':'stash'});
				if (data.temporary_session != '') {
					params[0] = data.temporary_session;
					req = obj.bare_request(app,name,params);
				}
			}
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
		return req;
	},

}

/*
function sample_callback(request) {
	var result = request.getResultObject();
}
*/

dump('exiting util/network.js\n');
