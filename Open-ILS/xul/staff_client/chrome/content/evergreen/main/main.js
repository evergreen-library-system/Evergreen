dump('entering main/main.js\n');

function main_init() {
	dump('entering main_init()\n');
	try {
		if (typeof JSAN == 'undefined') {
			throw(
				"The JSAN library object is missing."
			);
		}
		/////////////////////////////////////////////////////////////////////////////

		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('..');

		//JSAN.use('test.test'); test.test.hello_world();

		var mw = self;
		var G =  {};
		G.OpenILS = {};
		G.OpenSRF = {};

		JSAN.use('util.error');
		G.error = new util.error( mw, G );

		JSAN.use('main.window');
		G.window = new main.window( mw, G );

		JSAN.use('main.network');
		G.network = new main.network( mw, G );

		G.test_array = [ "a", "b", "c" ];
		G.test_object = { "a" : "b", "c" : "d", "e" : "f" };
		G.test = function(t) {
			dump(js2JSON( t ) + '\n');
		}

		JSAN.use('auth.controller');
		G.auth = new auth.controller( mw, G );

		G.auth.on_login = function() {

			JSAN.use('OpenILS.data');
			G.OpenILS.data = new OpenILS.data( mw, G );
			G.OpenILS.data.on_complete = function () {

				G.window.open('http://gapines.org/xul/test.xul','test','chrome');
			}
			G.OpenILS.data.init();
		}

		G.auth.init();

		/////////////////////////////////////////////////////////////////////////////

	} catch(E) {
		var error = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\n" + E + '\n';
		try { G.error.sdump('D_ERROR',error); } catch(E) { dump(error); }
		alert(error);
	}
	dump('exiting main_init()\n');
}

dump('exiting main/main.js\n');
