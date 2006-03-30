dump('entering util/widgets.js\n');

if (typeof util == 'undefined') var util = {};
util.widgets = {};

util.widgets.EXPORT_OK	= [ 
	'get',
	'save_xml',
	'serialize_node',
	'xul_from_string',
	'store_disable',
	'restore_disable',
	'disable',
	'get_list_from_tree_selection',
	'disable_accesskeys_in_node_and_children', 
	'enable_accesskeys_in_node_and_children', 
	'remove_children',
	'make_grid',
	'make_menulist',
	'insertAfter',
	'apply_vertical_tab_on_enter_handler',
	'vertical_tab',
	'click',
	'dispatch',
];
util.widgets.EXPORT_TAGS	= { ':all' : util.widgets.EXPORT_OK };

util.widgets.get = function(e) {
	if (typeof e == 'object') {
		return e;
	} else {
		return document.getElementById(e);
	}
}

util.widgets.save_xml = function (filename,node) {
	netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

	JSAN.use('util.file'); var file = new util.file(filename);

	node = util.widgets.get(node);
	var xml = util.widgets.serialize_node(node);

	file.write_content('truncate',xml);
	file.close();
}

util.widgets.serialize_node = function(node) {
	var serializer = new XMLSerializer();
	var xml = serializer.serializeToString(node);
	return xml;
}

util.widgets.xul_from_string = function(xml) {
	var parser = new DOMParser(); 
	var doc = parser.parseFromString(xml, "text/xml"); 
	var node = doc.documentElement;
	return node;
}

util.widgets.store_disable = function() {
	for (var i = 0; i < arguments.length; i++) {
		var e = util.widgets.get( arguments[i] );
		e.setAttribute('_disabled',e.getAttribute('disabled'));
	}
}

util.widgets.restore_disable = function() {
	for (var i = 0; i < arguments.length; i++) {
		var e = util.widgets.get( arguments[i] );
		e.setAttribute('disabled',e.getAttribute('_disabled'));
	}
}

util.widgets.disable = function() {
	for (var i = 0; i < arguments.length; i++) {
		var e = util.widgets.get( arguments[i] );
		e.setAttribute('disabled',true);
	}
}

util.widgets.click = function(e) {
	var evt = document.createEvent("MouseEvent");
	evt.initMouseEvent( "click", true, true, window, 0, 0, 0, 0, 0, false,false,false,false,0,null);
	util.widgets.get(e).dispatchEvent(evt);
}

util.widgets.dispatch = function(ev,el) {
	var evt = document.createEvent("Events");
	//var evt = document.createEvent();
	evt.initEvent( ev, true, true );
	util.widgets.get(el).dispatchEvent(evt);
}

util.widgets.make_menulist = function( items, dvalue ) {
	var menulist = document.createElement('menulist');
	var menupopup = document.createElement('menupopup'); menulist.appendChild(menupopup);
	for (var i = 0; i < items.length; i++) {
		var label = items[i][0]; var value = items[i][1]; var disabled = items[i][2]; var indent = items[i][3];
		if (indent) {
			for (var j = 0; j < Number(indent); j++) {
				label = ' ' + label;
			}
		}
		var menuitem = document.createElement('menuitem'); menupopup.appendChild(menuitem);
		menuitem.setAttribute('label',label);
		menuitem.setAttribute('value',value);
		if ( (disabled == true) || (disabled == "true") ) {
			menuitem.disabled = true;
			menuitem.setAttribute('disabled','true');
		}
	}
	menulist.setAttribute('value',dvalue);
	return menulist;
}

util.widgets.make_grid = function( cols ) {
	var grid = document.createElement('grid');
	var columns = document.createElement('columns'); grid.appendChild(columns);
	for (var i = 0; i < cols.length; i++) {
		var column = document.createElement('column'); columns.appendChild(column);
		for (var j in cols[i]) {
			column.setAttribute(j,cols[i][j]);
		}
	}
	var rows = document.createElement('rows'); grid.appendChild(rows);
	return grid;
}

util.widgets.get_list_from_tree_selection = function(tree_w) {
	var hitlist;
	var tree = util.widgets.get(tree_w);
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

util.widgets.remove_children = function() {
	for (var i = 0; i < arguments.length; i++) {
		var e = util.widgets.get( arguments[i] );
		while(e.lastChild) e.removeChild( e.lastChild );
	}
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

util.widgets.insertAfter = function(parent_node,new_node,sibling_node) {
	sibling_node = sibling_node.nextSibling;
	if (sibling_node) {
		parent_node.insertBefore(new_node,sibling_node);
	} else {
		parent_node.appendChild(new_node);
	}
}

util.widgets.apply_vertical_tab_on_enter_handler = function(node,onfailure) {
	try {
		node.addEventListener(
			'keypress',
			function(ev) {
				dump('keypress: ev.target.tagName = ' + ev.target.tagName 
					+ ' ev.target.nodeName = ' + ev.target.nodeName 
					+ ' ev.keyCode = ' + ev.keyCode 
					+ ' ev.charCode = ' + ev.charCode + '\n');
				if (ev.keyCode == 13) {
					dump('trying vertical tab\n');
					if (util.widgets.vertical_tab(ev.target)) {
						ev.preventDefault(); ev.stopPropagation();
						return true;
					} else {
						if (typeof onfailure == 'function') onfailure(ev);
						return util.widgets.vertical_tab(ev.target);
					}
				}
			},
			false
		);
	} catch(E) {
		alert(E);
	}
}

util.widgets.vertical_tab = function(node) {
	try {
		var rel_vert_pos = node.getAttribute('rel_vert_pos') || 0;
		dump('vertical_tab -> node = ' + node.nodeName + ' rel_vert_pos = ' + rel_vert_pos + '\n');

		var nl = document.getElementsByTagName( node.nodeName );

		var found_self = false; var next_node; var max_rel_vert_pos = 0;
		for (var i = 0; i < nl.length; i++) {

			var candidate_node = nl[i];
			var test_rel_vert_pos = candidate_node.getAttribute('rel_vert_pos') || 0;

			if (found_self && !next_node && (test_rel_vert_pos == rel_vert_pos) && !candidate_node.disabled) {
			
				next_node = candidate_node;

			}
			if (candidate_node == node) found_self = true;

			if (test_rel_vert_pos > max_rel_vert_pos) max_rel_vert_pos = test_rel_vert_pos;
		}

		dump('intermediate: next_node = ' + next_node + ' max_rel_vert_pos = ' + max_rel_vert_pos + '\n');

		if (!next_node) {

			found_self = false;
			for (var next_pos = rel_vert_pos; next_pos <= max_rel_vert_pos; next_pos++) {

				for (var i = 0; i < nl.length; i++) {
					var candidate_node = nl[i];
					var test_rel_vert_pos = candidate_node.getAttribute('rel_vert_pos') || 0;

					if (found_self && !next_node && (test_rel_vert_pos == next_pos) && !candidate_node.disabled ) {
						next_node = candidate_node;
					}

					if (candidate_node == node) found_self = true;
				}

			}

		}

		if (next_node) {
			dump('focusing\n');
			next_node.focus();
		}
		return next_node;
	} catch(E) {
		alert(E);
	}
}


dump('exiting util/widgets.js\n');
