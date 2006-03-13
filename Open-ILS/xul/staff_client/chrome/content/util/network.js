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
		try {
			var obj = this;
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
						obj.error.sdump('D_SES_RESULT','asynced result #' + obj.link_id + '\n\n' + 
							js2JSON(req.getResultObject()));
							obj.test_session_timeout(req);
						f(req);
					}
				);
				request.send(false);
				return null;
			} else {
				request.send(true);
				obj.test_session_timeout(request);
				var result = request.getResultObject();
				this.error.sdump('D_SES_RESULT','synced result #' + obj.link_id + '\n\n' + js2JSON(result));
				return result;
			}

		} catch(E) {
			if (instanceOf(E,perm_ex)) {
				alert('permission exception: ' + js2JSON(E));
			}
			throw(E);
		}
	},

	'test_session_timeout' : function(req) {
		try {
			var robj = req.getResultObject();
			if (robj.ilsevent && robj.ilsevent == 1001) {
				alert("Your session has timed out.  In the future we may give you the ability to log back in without losing your work, but for now, the behavior at this point is undefined and this message will almost certainly be followed by error messages.  Please logout of the staff client and then back in.");
			}
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
	}
}

/*
function sample_callback(request) {
	var result = request.getResultObject();
}
*/

dump('exiting util/network.js\n');
