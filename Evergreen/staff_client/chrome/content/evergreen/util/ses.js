sdump('D_TRACE','Loading ses.js\n');

//////////////////////////////////////////////////////////////////////////////
// Sessions, Requests, Methods, Oh My

// These wrap Bill's RemoteRequest.js

function user_request(app,name,params) {
	sdump('D_SES','=-=-=-=-= user_request("'+app+'","'+name+'",'+js2JSON(params)+')\n');
	var request = new RemoteRequest( app, name );
	for(var index in params) {
		request.addParam(params[index]);
	}
	request.send(true);
	var result = [];
	result.push( request.getResultObject() );
	//sdump('D_SES','=-=-= result = ' + js2JSON(result[0]) + '\n');
	return result;
}

function user_async_request(app,name,params,func) {
	sdump('D_SES','=-=-=-=-= user_async_request("'+app+'","'+name+'",'+js2JSON(params)+',func)\n');
	sdump('D_SES_FUNC','func = ' + func + '\n');
	var request = new RemoteRequest( app, name );
	for(var index in params) {
		request.addParam(params[index]);
	}
	request.setCompleteCallback(func);
	request.send();
}

function sample_func(request) {
	var result = [];
	result.push( request.getResultObject() );
	/* This callback would be called within the code for the Request object, so you would never see
	a return value.  Instead, you should _do_ something with the data. */
	return result;
}

//////////////////////////////////////////////////////////////////////////////
// The functions below were wrappers for the old jabber way of doing things

function handle_session(app) {
	//if( ses == null || ! AppSession.transport_handle.connected() ) {
	sdump('D_TRACE','Calling new AppSession : ' + timer_elapsed('cat') + '\n');
		ses = new AppSession( app );
		sdump('D_SES', 'after AppSession ses = ' + (ses.state) + '\n' );
		if( ! ses.connect() ) { 
			sdump('D_SES', 'after ses.connect ses = ' + js2JSON(ses.state) + '\n' );
			throw( "Connect timed out!" ); 
		}
		sdump('D_SES', 'after ses.connect ses = ' + js2JSON(ses.state) + '\n' );
	sdump('D_TRACE','Finished new AppSession : ' + timer_elapsed('cat') + '\n');
	//}
}

function handle_request(ses,meth) {


	sdump('D_TRACE','Entering handle_request : ' + timer_elapsed('cat') + '\n');
	sdump('D_SES','Calling new AppRequest : ' + timer_elapsed('cat') + '\n');

	var req = new AppRequest( ses, meth );

	sdump('D_SES','Finished new AppRequest : ' + timer_elapsed('cat') + '\n');
	sdump('D_SES','Calling new req.make_request() : ' + timer_elapsed('cat') + '\n');

	req.make_request();

	sdump('D_SES', 'after req.make_request ses = ' + js2JSON(ses.state) + '\n' );
	sdump('D_SES','Finished new req.make_request() : ' + timer_elapsed('cat') + '\n');

	var result = new Array(); var resp;

	sdump('D_SES','Looping on req.recv and resp.getContent(): ' + timer_elapsed('cat') + '\n');

	while (resp = req.recv( 30000 ) ) {
		sdump('D_SES', '\tafter req.recv ses = ' + js2JSON(ses.state) + ' : req.is_complete = ' + req.is_complete + '\n' );
		var r = resp.getContent();
		if (r != 'keepalive') {
			result.push( r );
		}
	}

	sdump('D_SES','Finished with req.recv and resp.getContent(): ' + timer_elapsed('cat') + '\n');

	if (result.length == 0) {
		if ( req.is_complete ) {
			result.push("NO RESPONSE, REQUEST COMPLETE");
			sdump('D_SES',"NO RESPONSE, REQUEST COMPLETE\n");
		} else {
			result.push("NO RESPONSE, REQUEST TIMEOUT");
			sdump('D_SES',"NO RESPONSE, REQUEST TIMEOUT\n");
		}
	}
	req.finish();
	sdump('D_SES', 'after req.finish() ses = ' + js2JSON(ses.state) + '\n' );
	sdump('D_SES','Exiting handle_request : ' + timer_elapsed('cat') + '\n');
	return result;	
}

function _user_request(app,name,params) {

	sdump('D_SES','Entering user_request : ' + timer_elapsed('cat') + '\n');
	sdump('D_SES','app='+app+' name='+name+'\n');
	try {

		handle_session(app);

		var meth;
		if (name) {
			meth = new oilsMethod( name, params );
		} else {
			throw('No method name to execute.');
		}

		var result = handle_request(ses,meth);
		
		if (ses) { 
			sdump('D_SES','ses.disconnect\n'); 
			ses.disconnect(); 
			sdump('D_SES', 'after ses.disconnect() ses = ' + js2JSON(ses.state) + '\n' );
			ses.destroy();
			sdump('D_SES', 'after ses.destroy() ses = ' + js2JSON(ses.state) + '\n' );
		}

		sdump('D_SES','Exiting user_request : ' + timer_elapsed('cat') + '\n');
		return result;

	} catch( E ) { 
		sdump('D_SES','Exiting user_request : ' + timer_elapsed('cat') + '\n');
		alert( pretty_print( js2JSON(E) ) ); 
		return null;
	}

}

