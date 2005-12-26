dump('entering util/widgets.js\n');

if (typeof util == 'undefined') var util = {};
util.widgets = {};

util.widgets.EXPORT_OK	= [ 
	'disable_accesskeys_in_node_and_children', 
	'enable_accesskeys_in_node_and_children', 
];
util.widgets.EXPORT_TAGS	= { ':all' : util.widgets.EXPORT_OK };

util.widgets.disable_accesskeys_in_node_and_children = function( node ) {
	if (node.getAttribute('accesskeys')) {
		node.setAttribute('oldaccesskeys', node.getAttribute('accesskeys'));
		node.setAttribute('accesskeys','');
	}
	for (var i = 0; i < node.childNodes.length; i++) {
		util.widgets.disable_accesskeys_in_node_and_children( node.childNodes[i] );
	}
}

util.widgets.enable_accesskeys_in_node_and_children = function( node ) {
	if (node.getAttribute('oldaccesskeys')) {
		node.setAttribute('accesskeys', node.getAttribute('oldaccesskeys'));
		node.setAttribute('oldaccesskeys','');
	}
	for (var i = 0; i < node.childNodes.length; i++) {
		util.widgets.enable_accesskeys_in_node_and_children( node.childNodes[i] );
	}
}

dump('exiting util/widgets.js\n');
