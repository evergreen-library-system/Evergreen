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
					+ '&desc_full=' + window.escape('Please re-login.  If after you have re-authenticated, you still see session expired dialogs like this one, please note where they are occuring and notify your friendly Evergreen developers.'),
					'simple_auth',
					'chrome,resizable,modal,width=300,height=300'
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
	}
}

/*
function sample_callback(request) {
	var result = request.getResultObject();
}
*/

dump('exiting util/network.js\n');
