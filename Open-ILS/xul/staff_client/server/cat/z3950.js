dump('entering cat.z3950.js\n');

if (typeof cat == 'undefined') cat = {};
cat.z3950 = function (params) {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		JSAN.use('util.error'); this.error = new util.error();
	} catch(E) {
		dump('cat.z3950: ' + E + '\n');
	}
}

cat.z3950.prototype = {

	'init' : function( params ) {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

			var obj = this;

			obj.session = params['session'];

			JSAN.use('util.controller'); obj.controller = new util.controller();
			obj.controller.init(
				{
					control_map : {
						'cmd_broken' : [
							['command'],
							function() { alert('Not Yet Implemented'); }
						],
					}
				}
			);

		} catch(E) {
			this.error.sdump('D_ERROR','cat.z3950.init: ' + E + '\n');
		}
	},
}

dump('exiting cat.z3950.js\n');
