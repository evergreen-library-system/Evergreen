dump('Loading ses.js\n');

//////////////////////////////////////////////////////////////////////////////
// Sessions, Requests, Methods, Oh My

function handle_session(app) {
	//if( ses == null || ! AppSession.transport_handle.connected() ) {
	dump('Calling new AppSession : ' + timer_elapsed('cat') + '\n');
		ses = new AppSession( app );
		dump( 'after AppSession ses = ' + (ses.state) + '\n' );
		if( ! ses.connect() ) { 
			dump( 'after ses.connect ses = ' + js2JSON(ses.state) + '\n' );
			throw( "Connect timed out!" ); 
		}
		dump( 'after ses.connect ses = ' + js2JSON(ses.state) + '\n' );
	dump('Finished new AppSession : ' + timer_elapsed('cat') + '\n');
	//}
}

function handle_request(ses,meth) {


	dump('Entering handle_request : ' + timer_elapsed('cat') + '\n');
	dump('Calling new AppRequest : ' + timer_elapsed('cat') + '\n');

	var req = new AppRequest( ses, meth );

	dump('Finished new AppRequest : ' + timer_elapsed('cat') + '\n');
	dump('Calling new req.make_request() : ' + timer_elapsed('cat') + '\n');

	req.make_request();

	dump( 'after req.make_request ses = ' + js2JSON(ses.state) + '\n' );
	dump('Finished new req.make_request() : ' + timer_elapsed('cat') + '\n');

	var result = new Array(); var resp;

	dump('Looping on req.recv and resp.getContent(): ' + timer_elapsed('cat') + '\n');

	while (resp = req.recv( 30000 ) ) {
		dump( '\tafter req.recv ses = ' + js2JSON(ses.state) + ' : req.is_complete = ' + req.is_complete + '\n' );
		var r = resp.getContent();
		if (r != 'keepalive') {
			result.push( r );
		}
	}

	dump('Finished with req.recv and resp.getContent(): ' + timer_elapsed('cat') + '\n');

	if (result.length == 0) {
		if ( req.is_complete ) {
			result.push("NO RESPONSE, REQUEST COMPLETE");
			dump("NO RESPONSE, REQUEST COMPLETE\n");
		} else {
			result.push("NO RESPONSE, REQUEST TIMEOUT");
			dump("NO RESPONSE, REQUEST TIMEOUT\n");
		}
	}
	req.finish();
	dump( 'after req.finish() ses = ' + js2JSON(ses.state) + '\n' );
	dump('Exiting handle_request : ' + timer_elapsed('cat') + '\n');
	return result;	
}




function user_request(app,name,params) {
	dump('=-=-=-=-= user_request:\n');
	dump('request '+(app)+' '+(name)+' '+js2JSON(params)+'\n');
	var request = new RemoteRequest( app, name );
	for(var index in params) {
		request.addParam(params[index]);
	}
	request.send(true);
	var result = [];
	result.push( request.getResultObject() );
	//dump('=-=-= result = ' + js2JSON(result[0]) + '\n');
	return result;
}

function user_async_request(app,name,params,func) {
	dump('=-=-=-=-= user_async_request: ' + js2JSON(func) + '\n');
	dump('request '+(app)+' '+(name)+' '+js2JSON(params)+'\n');
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

function _user_request(app,name,params) {

	dump('Entering user_request : ' + timer_elapsed('cat') + '\n');
	dump('app='+app+' name='+name+'\n');
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
			dump('ses.disconnect\n'); 
			ses.disconnect(); 
			dump( 'after ses.disconnect() ses = ' + js2JSON(ses.state) + '\n' );
			ses.destroy();
			dump( 'after ses.destroy() ses = ' + js2JSON(ses.state) + '\n' );
		}

		dump('Exiting user_request : ' + timer_elapsed('cat') + '\n');
		return result;

	} catch( E ) { 
		dump('Exiting user_request : ' + timer_elapsed('cat') + '\n');
		alert( pretty_print( js2JSON(E) ) ); 
		return null;
	}

}

