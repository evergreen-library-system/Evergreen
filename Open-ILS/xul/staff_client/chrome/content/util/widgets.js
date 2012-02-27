dump('entering util/widgets.js\n');

if (typeof util == 'undefined') var util = {};
util.widgets = {};

util.widgets.EXPORT_OK    = [ 
    'get',
    'apply',
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
    'stop_event',
    'set_text',
    'save_attributes',
    'load_attributes',
    'find_descendants_by_name',
    'render_perm_org_menu'
];
util.widgets.EXPORT_TAGS    = { ':all' : util.widgets.EXPORT_OK };

util.widgets.get = function(e) {
    if (typeof e == 'object') {
        return e;
    } else {
        return document.getElementById(e);
    }
}

util.widgets.apply = function(e,attr,attr_value,f) {
    var node = util.widgets.get(e);
    var nl = node.getElementsByAttribute(attr,attr_value);
    for (var i = 0; i < nl.length; i++) {
        f( nl[i] );
    }
}

util.widgets.save_xml = function (filename,node) {
    try { 
        JSAN.use('util.file'); var file = new util.file(filename);

        node = util.widgets.get(node);
        var xml = util.widgets.serialize_node(node);

        file.write_content('truncate',xml);
        file.close();
    } catch(E) {
        alert('Error in util.widgets.save_xml: ' + E);
    }
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
        if (typeof items[i] == 'undefined') { continue; }
        var label = items[i][0]; var value = items[i][1]; var disabled = items[i][2]; var indent = items[i][3];
        if (indent) {
            for (var j = 0; j < Number(indent); j++) {
                //label = ' ' + label;
            }
        }
        var menuitem = document.createElement('menuitem'); menupopup.appendChild(menuitem);
        menuitem.setAttribute('label',label);
        menuitem.setAttribute('value',value);
        if (indent) {
            menuitem.setAttribute('style','font-family: monospace; padding-left: ' + indent + 'em;');
        } else {
            menuitem.setAttribute('style','font-family: monospace;');
        }
        if ( (disabled == true) || (disabled == "true") ) {
            menuitem.disabled = true;
            menuitem.setAttribute('disabled','true');
        }
    }
    if (typeof dvalue != 'undefined') {
        menulist.setAttribute('value',dvalue);
    }
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
    return; /* what was I doing here? */
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
    return; /* what was I doing here? */
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

util.widgets.apply_vertical_tab_on_enter_handler = function(node,onfailure,no_enter_func) {
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
                        dump('keypress: attempting onfailure\n');
                        if (typeof onfailure == 'function') return onfailure(ev);
                        return false;
                    }
                } else {
                    if (typeof no_enter_func == 'function') {
                        if ([
                                35 /* end */,
                                36 /* home */,
                                37 /* left */,
                                38 /* up */,
                                39 /* right */,
                                40 /* down */,
                                9 /* tab */
                            ].indexOf(ev.keyCode) == -1
                        ) {
                            // really the no_enter, no_arrow_key, no_tab, etc. func :)
                            no_enter_func(ev);
                        }
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

util.widgets.stop_event = function(ev) {
    ev.preventDefault();
    return false;
}

util.widgets.set_text = function(n,t) {
    n = util.widgets.get(n);
    switch(n.nodeName) {
        case 'button' :
        case 'caption' :
            n.setAttribute('label',t);
        break;
        case 'label' : 
            n.setAttribute('value',t); 
        break;
        case 'description' : 
        case 'H1': case 'H2': case 'H3': case 'H4': case 'SPAN': case 'P': case 'BLOCKQUOTE':
            util.widgets.remove_children(n); 
            n.appendChild( document.createTextNode(t) );
        break;
        case 'textbox' :
            n.value = t; n.setAttribute('value',t);
        break;
        default:
            alert("FIXME: util.widgets.set_text doesn't know how to handle " + n.nodeName);
        break;
    }
}

util.widgets.get_text = function(n) {
    n = util.widgets.get(n);
    switch(n.nodeName) {
        case 'button' :
        case 'caption' :
            return n.getAttribute('label');
        break;
        case 'label' : 
            return n.getAttribute('value'); 
        break;
        case 'description' : 
        case 'H1': case 'H2': case 'H3': case 'H4': case 'SPAN': case 'P': case 'BLOCKQUOTE':
            return n.textContent;
        break;
        case 'textbox' :
            return n.value;
        break;
        default:
            alert("FIXME: util.widgets.get_text doesn't know how to handle " + n.nodeName);
            return null;
        break;
    }
}

util.widgets.save_attributes = function (file,ids_attrs) {
    try {
        var blob = {};
        for (var element_id in ids_attrs) {
            var attribute_list = ids_attrs[ element_id ];
            if (! blob[ element_id ] ) blob[ element_id ] =  {};
            var x = document.getElementById( element_id );
            if (x) {
                for (var j = 0; j < attribute_list.length; j++) {
                    blob[ element_id ][ attribute_list[j] ] = x.getAttribute( attribute_list[j] );
                }
            } else {
                dump('Error in util.widgets.save_attributes('+file._file.path+','+js2JSON(ids_attrs)+'):\n');
                dump('\telement_id = ' + element_id + '\n');
            }
        }
        //FIXME - WHY DOES THIS NOT WORK?// JSAN.use('util.file'); var file = new util.file(filename);
        file.set_object(blob); file.close();
    } catch(E) {
        alert('Error saving preferences: ' + E);
    }
}

util.widgets.load_attributes = function (file) {        
    try {
        //FIXME - WHY DOES THIS NOT WORK?// JSAN.use('util.file'); var file = new util.file(filename);
        if (file._file.exists()) {
            var blob = file.get_object(); file.close();
            for (var element_id in blob) {
                for (var attribute in blob[ element_id ]) {
                    var x = document.getElementById( element_id );
                    if (x) {
                        if (x.nodeName == 'menulist' && attribute == 'value') {
                            var popup = x.firstChild;
                            var children = popup.childNodes;
                            for (var i = 0; i < children.length; i++) {
                                if (children[i].getAttribute('value') == blob[ element_id ][ attribute ]) {
                                    dump('setting ' + x.nodeName + ' ' + element_id + ' @value to ' + blob[ element_id ][ attribute ] + '\n' );
                                    x.setAttribute(attribute, blob[ element_id ][ attribute ]);
                                }
                            }
                        } else {
                            dump('setting ' + x.nodeName + ' ' + element_id + ' @value to ' + blob[ element_id ][ attribute ] + '\n');
                            x.setAttribute(attribute, blob[ element_id ][ attribute ]);
                        }
                    } else {
                        dump('Error in util.widgets.load_attributes('+file._file.path+'):\n');
                        dump('\telement_id = ' + element_id + '\n');
                        dump('\tattribute = ' + attribute + '\n');
                        dump('\tblob[id][attr] = ' + blob[element_id][attribute] + '\n');
                    }
                }
            }
            return blob;
        }
        return {};
    } catch(E) {
        alert('Error loading preferences: ' + E);
    }
}

util.widgets.addProperty = function(e,c) {
	if(!e || !c) return;

	var prop_class_string = e.getAttribute('properties');
	var prop_class_array;

	if(prop_class_string)
		prop_class_array = prop_class_string.split(/\s+/);

	var string_ip = ""; /*strip out nulls*/
	for (var prop_class in prop_class_array) {
		if (prop_class_array[prop_class] == c) { return; }
		if(prop_class_array[prop_class] !=null)
			string_ip += prop_class_array[prop_class] + " ";
	}
	string_ip += c;
	e.setAttribute('properties',string_ip);
}

util.widgets.removeProperty = function(e, c) {
	if(!e || !c) return;

	var prop_class_string = '';

	var prop_class_array = e.getAttribute('properties');
	if( prop_class_array )
		prop_class_array = prop_class_array.split(/\s+/);

	var first = 1;
	for (var prop_class in prop_class_array) {
		if (prop_class_array[prop_class] != c) {
			if (first == 1) {
				prop_class_string = prop_class_array[prop_class];
				first = 0;
			} else {
				prop_class_string = prop_class_string + ' ' +
					prop_class_array[prop_class];
			}
		}
	}
	e.setAttribute('properties', prop_class_string);
}

util.widgets.find_descendants_by_name = function(top_node,name) {
    top_node = util.widgets.get(top_node);
    if (!top_node) { return []; }
    return top_node.getElementsByAttribute('name',name);
}

util.widgets.render_perm_org_menu = function (perm,org) {
    try {
        JSAN.use('util.functional'); JSAN.use('util.fm_utils');
        JSAN.use('OpenILS.data'); JSAN.use('util.network');
        var data = new OpenILS.data(); data.stash_retrieve();
        var network = new util.network();

        var work_ous = network.simple_request(
            'PERM_RETRIEVE_WORK_OU',
            [ ses(), perm]
        );
        if (work_ous.length == 0) {
            return false;
        }

        var my_libs = [];
        for (var i = 0; i < work_ous.length; i++ ) {
            var perm_depth = data.hash.aout[ data.hash.aou[ work_ous[i] ].ou_type() ].depth();

            var my_libs_tree = network.simple_request(
                'FM_AOU_DESCENDANTS_RETRIEVE',
                [ work_ous[i], perm_depth ]
            );
            if (!instanceOf(my_libs_tree,aou)) { /* FIXME - workaround for weird descendants call result */
                my_libs_tree = my_libs_tree[0];
            }
            my_libs = my_libs.concat( util.fm_utils.flatten_ou_branch( my_libs_tree ) );
        }

        var default_lib = org || my_libs[0].id();

        var ml = util.widgets.make_menulist(
            util.functional.map_list(
                my_libs,
                function(obj) {
                    return [
                        obj.shortname() + ' : ' + obj.name(),
                        obj.id(),
                        false,
                        ( data.hash.aout[ obj.ou_type() ].depth() )
                    ];
                }
            ),
            default_lib
        );

        return ml;

    } catch(E) {
        alert('Error in util.widgets.render_perm_org_menu(): ' + E);
    }
}
dump('exiting util/widgets.js\n');
