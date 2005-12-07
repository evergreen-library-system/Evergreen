dump('entering util/exec.js\n');

if (typeof util == 'undefined') var util = {};
util.exec = function() {
	//JSAN.use('util.error'); this.error = new util.error();

	return this;
};

util.exec.prototype = {
	// This executes a series of functions, but tries to give other events/functions a chance to
	// execute between each one.
	'chain' : function () {
		var args = [];
		var obj = this;
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
				try {
					args[0]();
					if (args.length > 1 ) obj.chain( args.slice(1) );
				} catch(E) {
					dump('util.exec.chain broken: ' + E + '\n');
					if (typeof obj.on_error == 'function') {
						obj.on_error(E);
					}
				}
			}, 0
		);
	}
}

dump('exiting util/exec.js\n');
