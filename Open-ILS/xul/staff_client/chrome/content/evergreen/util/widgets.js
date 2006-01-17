dump('entering util/widgets.js\n');

if (typeof util == 'undefined') var util = {};
util.widgets = {};

util.widgets.EXPORT_OK	= [ 
	'get_list_from_tree_selection',
	'disable_accesskeys_in_node_and_children', 
	'enable_accesskeys_in_node_and_children', 
];
util.widgets.EXPORT_TAGS	= { ':all' : util.widgets.EXPORT_OK };

util.widgets.get_list_from_tree_selection = function(tree_w) {
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

util.widgets.disable_accesskeys_in_node_and_children = function( node ) {
	if (node.getAttribute('accesskey')) {
		node.setAttribute('oldaccesskey', node.getAttribute('accesskey'));
		node.setAttribute('accesskey',''); node.accessKey = '';
	}
	for (var i = 0; i < node.childNodes.length; i++) {
		util.widgets.disable_accesskeys_in_node_and_children( node.childNodes[i] );
	}
	dump('- node = <' + node.id + '> accesskey = <' + node.accessKey + '> accesskey = <' + node.getAttribute('accesskey') + '> oldaccesskey = <' + node.getAttribute('oldaccesskey') + '>\n');
}

util.widgets.enable_accesskeys_in_node_and_children = function( node ) {
	if (node.getAttribute('oldaccesskey')) {
		node.setAttribute('accesskey', node.getAttribute('oldaccesskey'));
		node.accessKey = node.getAttribute('oldaccesskey'); 
		node.setAttribute('oldaccesskey','');
	}
	for (var i = 0; i < node.childNodes.length; i++) {
		util.widgets.enable_accesskeys_in_node_and_children( node.childNodes[i] );
	}
	dump('+ node = <' + node.id + '> accesskey = <' + node.accessKey + '> accesskey = <' + node.getAttribute('accesskey') + '> oldaccesskey = <' + node.getAttribute('oldaccesskey') + '>\n');
}

dump('exiting util/widgets.js\n');
