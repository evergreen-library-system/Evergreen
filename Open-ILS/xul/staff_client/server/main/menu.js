dump('entering main/menu.js\n');

if (typeof main == 'undefined') main = {};
main.menu = function () {

	JSAN.use('util.error'); this.error = new util.error();

	this.w = window;
}

main.menu.prototype = {

	'init' : function() {

		var obj = this;

		var cmd_close_window = this.w.document.getElementById('cmd_close_window');
			if (cmd_close_window) 
				cmd_close_window.addEventListener('command', function() { obj.w.close(); }, false);
			
		var cmd_new_window = this.w.document.getElementById('cmd_new_window');
			if (cmd_new_window)
				cmd_new_window.addEventListener('command', function() { alert('Not Yet Implemented'); }, false);

		var cmd_broken = this.w.document.getElementById('cmd_broken');
			if (cmd_broken)
				cmd_broken.addEventListener('command', function() { alert('Not Yet Implemented'); }, false);
		
	},

	'close_tab' : function (t_idx) {
	}

}

dump('exiting main/menu.js\n');
