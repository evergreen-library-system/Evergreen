dump('entering util/exec.js\n');

if (typeof util == 'undefined') var util = {};
util.exec = function(chunk_size) {
	//JSAN.use('util.error'); this.error = new util.error();

	this.chunk_size = chunk_size || 1;

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
					for (var i = 0; (i < args.length && i < obj.chunk_size) ; i++) {
						try {
							if (typeof args[i] == 'function') {
								args[i]();
							} else {
								alert('FIXME -- typeof args['+i+'] == ' + typeof args[i]);
							}
						} catch(E) {
							dump('util.exec.chain error: ' + js2JSON(E) + '\n');
							var keep_going = false;
							if (typeof obj.on_error == 'function') {
								keep_going = obj.on_error(E);
							}
							if (keep_going) {
								dump('chain not broken\n');
								try {
									if (args.length > 1 ) obj.chain( args.slice(1) );

								} catch(E) {
									dump('another error: ' + js2JSON(E) + '\n');
								}
							} else {
								dump('chain broken\n');
							}
						}
					}
					if (args.length > obj.chunk_size ) obj.chain( args.slice(obj.chunk_size) );
				} catch(E) {
					alert(E);
				}
			}, 0
		);
	}
}

dump('exiting util/exec.js\n');
