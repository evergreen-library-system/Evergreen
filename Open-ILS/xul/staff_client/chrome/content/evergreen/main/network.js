dump('entering main/network.js\n');

if (typeof main == 'undefined') main = {};
main.network = function () {

	JSAN.use('util.error'); this.error = new util.error();
	// Place a test here for network connectivity
	// this.offline = true;

	return this;
};

main.network.prototype = {

	// Flag for whether the staff client should act as if it were offline or not
	'offline' : false,

	'request' : function (app,name,params,f) {

		try {

			this.error.sdump('D_SES','=-=-=-=-= user_request("'+app+'","'+name+'",'+js2JSON(params)+')\n');
			var request = new RemoteRequest( app, name );
			for(var index in params) {
				request.addParam(params[index]);
			}
	
			if (f)  {
				request.setCompleteCallback(f);
				request.send(false);
				this.error.sdump('D_SES_RESULT','=-=-= result asynced\n');
				return null;
			} else {
				request.send(true);
				var result = request.getResultObject();
				this.error.sdump('D_SES_RESULT','=-=-= result = ' + js2JSON(result) + '\n');
				return result;
			}

		} catch(E) {
			if (instanceOf(E,perm_ex)) {
				alert('permission exception: ' + js2JSON(E));
			}
			throw(E);
		}
	}
}

/*
function sample_callback(request) {
	var result = request.getResultObject();
}
*/

dump('exiting main/network.js\n');
