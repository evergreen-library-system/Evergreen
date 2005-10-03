dump('entering util/exec.js\n');

if (typeof util == 'undefined') var util = {};
util.exec = {};

util.exec.EXPORT_OK	= [ 'chain_exec' ];
util.exec.EXPORT_TAGS	= { ':all' : util.exec.EXPORT_OK };

// This executes a series of functions, but tries to give other events/functions a chance to
// execute between each one.
util.exec.chain = function () {
	var args = [];
	for (var i = 0; i < arguments.length; i++) {
		var arg = arguments[i];
		switch(arg.constructor.name) {
			case 'Function' :
				args.push( arg );
			break;
			case 'Array' :
				for (var j = 0; j < arg.length; j++) {
					if (typeof arg[j] == 'function') args.push( arg[j] );
				}
			break;
			case 'Object' :
				for (var j in arg) {
					if (typeof arg[j] == 'function') args.push( arg[j] );
				}
			break;
		}
	}
	if (args.length > 0) setTimeout(
		function() {
			args[0]();
			if (args.length > 1 ) util.exec.chain( args.slice(1) );
		}, 0
	);
}

dump('exiting util/exec.js\n');
