dump('entering main/menu.js\n');

if (typeof main == 'undefined') main = {};
main.menu = function () {

	JSAN.use('util.error'); this.error = new util.error();
	this.error.sdump('D_ERROR',window);

}

main.menu.prototype = {

	'init' : function() {

		var obj = this;

		var cmd_close_window = window.document.getElementById('cmd_close_window');
			if (cmd_close_window) {
				this.error.sdump('D_TRACE', 'cmd_close_window = ' + cmd_close_window );
				cmd_close_window.addEventListener('command', function() { dump('hiccup\n'); alert('help'); window.close(); }, false);
			}
			
		var test_button = window.document.getElementById('cmd_test_button');
			if (test_button) {
				this.error.sdump('D_TRACE', 'test_button = ' + test_button );
				test_button.addEventListener('command', function() { dump('hiccup\n'); alert('help'); window.close(); }, false);
			}

		var cmd_new_window = window.document.getElementById('cmd_new_window');
			if (cmd_new_window)
				cmd_new_window.addEventListener('command', function() { alert('Not Yet Implemented'); }, false);

		var cmd_broken = window.document.getElementById('cmd_broken');
			if (cmd_broken)
				cmd_broken.addEventListener('command', function() { alert('Not Yet Implemented'); }, false);
		
	},

	'close_tab' : function (t_idx) {
	}

}

dump('exiting main/menu.js\n');
