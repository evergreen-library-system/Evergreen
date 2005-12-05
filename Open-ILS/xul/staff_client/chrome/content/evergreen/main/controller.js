dump('entering main/controller.js\n');

if (typeof main == 'undefined') main = {};
main.controller = function () {

	JSAN.use('util.error'); this.error = new util.error();

	return this;
};

main.controller.prototype = {

	'init' : function (params) {

		if (typeof params.control_map == 'undefined') throw('main.controller.init: No control_map');

		this.control_map = params.control_map;
		this.render_list = [];
		this.view = {};
		
		for (var i in this.control_map) {
			var cmd = document.getElementById(i);
			if (cmd) {
				for (var j in this.control_map[i][0]) {
					if (this.control_map[i][1]) {
						var ev_type = this.control_map[i][0][j];
						switch(ev_type) {
							case 'render':
								this.render_list.push( this.control_map[i][1](cmd) ); 
							break;
							default: cmd.addEventListener(ev_type,this.control_map[i][1],false);
						}
					}
				}
			}
			this.view[i] = cmd;
		}
	},

	'render' : function() {
		for (var i in this.render_list) {
			try {
				this.render_list[i]();
			} catch(E) {
				var error = 'Problem in circ.checkout.render with\n' 
					+ this.render_list[i] + '\n\n' + js2JSON(E);
				this.error.sdump('D_ERROR',error);
			}
		}
	}
}
dump('exiting main/controller.js\n');
