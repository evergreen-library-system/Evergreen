dump('entering util/fm_utils.js\n');

if (typeof util == 'undefined') var util = {};
util.fm_utils = {};

util.fm_utils.EXPORT_OK	= [ 'flatten_ou_branch', 'find_ou' ];
util.fm_utils.EXPORT_TAGS	= { ':all' : util.fm_utils.EXPORT_OK };

util.fm_utils.flatten_ou_branch = function(branch) {
	var my_array = new Array();
	my_array.push( branch );
	for (var i in branch.children() ) {
		var child = branch.children()[i];
		if (child != null) {
			var temp_array = util.fm_utils.flatten_ou_branch(child);
			for (var j in temp_array) {
				my_array.push( temp_array[j] );
			}
		}
	}
	return my_array;
}

util.fm_utils.find_ou = function(tree,id) {
	if (typeof(id)=='object') { id = id.id(); }
	if (tree.id()==id) {
		return tree;
	}
	for (var i in tree.children()) {
		var child = tree.children()[i];
		ou = util.fm_utils.find_ou( child, id );
		if (ou) { return ou; }
	}
	return null;
}

