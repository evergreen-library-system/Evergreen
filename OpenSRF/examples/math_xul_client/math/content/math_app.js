// connect and stup

var ses;

function execute( opp ) {

	var a = document.getElementById("num1");
	var b = document.getElementById("num2");
	do_stuff( opp, a.value, b.value );

}

function do_stuff( opp, a, b ) {



	try {

		if( ses == null || ! AppSession.transport_handle.connected() ) {

			/* deprecated */
			ses = new AppSession( "user_name", "12345", "math" );
			if( ! ses.connect() ) { alert( "Connect timed out!" ); }
		}

		var meth = new oilsMethod(opp, [ a, b ] );

		var req = new AppRequest( ses, meth );
		req.make_request();
		var resp = req.recv( 5000 );
		if( ! resp ) {
			alert( "NO response from server!!!" );
			quit(); return;
		}
	
		var scalar = resp.getContent();
		var value = scalar.getValue();

		var lab = document.getElementById( "answer" );
		lab.value = "Answer: " + value;
		req.finish();

	} catch( E ) { alert( E.message ); }	

}


function quit() { ses.disconnect(); window.close(); }


