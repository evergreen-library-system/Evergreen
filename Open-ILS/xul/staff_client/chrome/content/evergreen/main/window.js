dump('entering main/window.js\n');

if (typeof main == 'undefined') main = {};
main.window = function (mw,G) {
	this.main_window = mw;
	return this;
};

main.window.prototype = {
	
	// pointer to the auth window
	'main_window' : null, 	

	// list of open window references, used for debugging in shell
	'win_list' : [],	

	// list of Top Level menu interface window references
	'appshell_list' : [],	

	// list of documents for debugging.  BROKEN
	'doc_list' : [],	

	// Windows need unique names.  This number helps.
	'window_name_increment' : 0, 

	// This number gets put into the title bar for Top Level menu interface windows
	'appshell_name_increment' : 0

}

dump('exiting main/window.js\n');
