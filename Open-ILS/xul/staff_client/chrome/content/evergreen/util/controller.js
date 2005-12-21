dump('entering util/controller.js\n');

if (typeof util == 'undefined') util = {};
util.controller = function () {

	JSAN.use('util.error'); this.error = new util.error();

	return this;
};

util.controller.prototype = {

	'cmds' : {},

	'init' : function (params) {

		if (typeof params.control_map == 'undefined') throw('util.controller.init: No control_map');

		this.control_map = params.control_map;
		this.window_knows_me_by = params.window_knows_me_by;
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
								this.render_list.push( [i, this.control_map[i][1](cmd)] ); 
							break;
							case 'on_command':
								if (!this.window_knows_me_by) 
									throw('util.controller: on_command requires window_knows_me_by');
								cmd.setAttribute(ev_type, this.window_knows_me_by . ".cmds." i . "()");	
							break;
							default: cmd.addEventListener(ev_type,this.control_map[i][1],false);
						}
					}
				}
			}
			this.view[i] = cmd;
		}
	},

	'render' : function(id) {
		for (var i in this.render_list) {
			try {
				if (id) {
					if (id == this.render_list[i][0]) this.render_list[i][1]();
				} else {
					this.render_list[i][1]();
				}
			} catch(E) {
				var error = 'Problem in circ.checkout.render with\n' 
					+ this.render_list[i] + '\n\n' + js2JSON(E);
				this.error.sdump('D_ERROR',error);
			}
		}
	}
}
dump('exiting util/controller.js\n');
