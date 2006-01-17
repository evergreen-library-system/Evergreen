dump('entering util/widgets.js\n');

if (typeof util == 'undefined') var util = {};
util.widgets = {};

util.widgets.EXPORT_OK	= [ 
	'get_list_from_tree_selection'
];
util.widgets.EXPORT_TAGS	= { ':all' : util.widgets.EXPORT_OK };

util.widget.get_list_from_tree_selection = function(tree_w) {
	var hitlist;
	if (typeof(tree_w) != 'object') {
		tree = document.getElementById(tree_w);
	} else {
		tree = tree_w;
	}
	var list = [];
	var start = new Object();
	var end = new Object();
	var numRanges = tree.view.selection.getRangeCount();
	for (var t=0; t<numRanges; t++){
		tree.view.selection.getRangeAt(t,start,end);
		for (var v=start.value; v<=end.value; v++){
			var i = tree.contentView.getItemAtIndex(v);
			list.push( i );
		}
	}
	return list;
}

dump('exiting util/widgets.js\n');
