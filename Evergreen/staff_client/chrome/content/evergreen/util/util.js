sdump('D_TRACE','Loading util.js\n');

var timer = {};
var counter = {};
var treeitem_id = 0;

var sdump_levels = {
	'D_TRACE' :  true,
	'D_AUTH' : false,
	'D_UTIL' : false,
	'D_EXPLODE' : false,
	'D_PRINT' : false,
	'D_SES' : true
};

function sdump(level,msg) {
	try {
		if (sdump_levels[level])
			debug(msg);
	} catch(E) {}
}

function handle_error(E) {
	var s = '';
	if (instanceOf(E,ex)) {
		s += E.err_msg();
		//s += '\n\n=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=\n\n';
		//s += 'This error was anticipated.\n\n';
		//s += js2JSON(E).substr(0,200) + '...\n\n';
		snd_bad()
	} else {
		s += '\n\n=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=\n\n';
		s += 'This is a bug that we will fix later.\n\n';
		s += js2JSON(E).substr(0,200) + '\n\n';
		snd_really_bad();
	}
	s_alert(s);
}

function string_to_array(s) {
	var my_array = [];
	for (var i = 0; i < s.length; i++ ) {
		my_array.push( s.charAt(i) );
	}
	return my_array;
}

function textbox_checkdigit(ev) {
	if ( check_checkdigit( ev.target.value ) ) {
		sdump('D_UTIL', 'success\n');
		return true;
	} else {
		sdump('D_UTIL', 'failure\n');
		ev.preventDefault();
		ev.stopPropagation();
		return false;
	}
}

function check_checkdigit(barcode) {

	var stripped_barcode = barcode.slice(0,-1);
	var checkdigit = barcode.slice(-1);

	sdump('D_UTIL', '\n\n=-=***=-=\n\ncheck_checkdigit: barcode = ' + barcode + ' barcode stripped = ' + stripped_barcode + ' checkdigit = ' + checkdigit + '\n');

	var sum = 0; var mul = 2;

	var b_array = string_to_array( stripped_barcode ).reverse();
	sdump('D_UTIL', '\tb_array = ' + b_array + '\n');

	for (var i in b_array) {
		var digit = parseInt( b_array[i] );
		sdump('D_UTIL', '\t\tdigit = ' + digit + '\n');

		var product = digit * mul;
		if (mul == 2) { mul = 1; } else { mul = 2; }

		var p_array = string_to_array( product.toString() );
		sdump('D_UTIL', '\t\tp_array = ' + p_array + '\n');

		for (var j in p_array) { 
			var n = parseInt( p_array[j] );
			sdump('D_UTIL', '\t\t\tn = ' + n + '\n');
			sum += n;
		}
	}

	sdump('D_UTIL', '\tsum = ' + sum + '\n');

	var s_array = string_to_array( sum.toString() );
	var calculated_checkdigit = s_array.pop();
	if (calculated_checkdigit > 0) calculated_checkdigit = 10 - calculated_checkdigit;
	sdump('D_UTIL', '\tcalculated checkdigit = ' + calculated_checkdigit + '\n\n=-=***=-=\n\n');

	return ( calculated_checkdigit == checkdigit );
}

function fake_tab_for_textboxes(w,current) {
	var flag = false; var next_one;
	if (typeof(w)!='object') {
		w = document.getElementById(w);
	}
	sdump('D_UTIL', 'fake_tab_for_textboxes: Current ' + current + '\n');
	var nl = w.getElementsByTagName('textbox');
	//var nl = document.getElementsByTagName('textbox');
	sdump('D_UTIL', 'fake_tab_for_textboxes: nl.length = ' + nl.length + '\n');
	for (var i = 0; i < nl.length; i++) {
		sdump('D_UTIL', 'fake_tab_for_textboxes: Considering ' + nl[i] + '...\n');
		if (flag && !next_one) {
			sdump('D_UTIL', 'fake_tab_for_textboxes: Setting next_one ' + nl[i] + '\n');	
			next_one = nl[i];
		}
		if (nl[i] === current) {
			sdump('D_UTIL','fake_tab_for_textboxes: Found current\n');
			flag = true;
		}
	}
	if (!next_one) {
		sdump('D_UTIL','fake_tab_for_textboxes: Out of loop, Setting next_one ' + nl[0] + '\n');	
		next_one = nl[0];
	}
	if (next_one) {
		next_one.focus(); next_one.select();
	} else {
		sdump('D_UTIL','fake_tab_for_textboxes: next_one not set\n');
	}
}

function get_list_from_tree_selection(tree_w) {
	sdump('D_UTIL','entering get_list_from_tree...\n');
	var hitlist;
	if (typeof(tree_w) != 'object') {
		hitlist = document.getElementById(tree_w);
	} else {
		hitlist = tree_w;
	}
	var list = [];
	var start = new Object();
	var end = new Object();
	var numRanges = hitlist.view.selection.getRangeCount();
	for (var t=0; t<numRanges; t++){
		hitlist.view.selection.getRangeAt(t,start,end);
		for (var v=start.value; v<=end.value; v++){
			var i = hitlist.contentView.getItemAtIndex(v);
			//sdump('D_UTIL',i.tagName + '\n');
			list.push( i );
		}
	}
	sdump('D_UTIL','leaving get_list_from_tree...\n');
	return list;
}

function yesno(value) {
	switch(value) {
		case true: case 'true': case '1': case 'on':
			return 'Yes';
		default: 
			return 'No';
	}
}

function formatted_date(date,format) {
	// pass in a Date object or epoch seconds
	if (typeof(date) == 'string') {
		date = new Date( parseInt( date + '000' ) );
	}
	var mm = date.getMonth() + 1;
	mm = mm.toString();
	if (mm.length == 1) mm = '0' +mm;
	var dd = date.getDate().toString();
	if (dd.length == 1) dd = '0' +dd;
	var yyyy = date.getFullYear().toString();
	var s = format.replace( /%m/g, mm );
	s = s.replace( /%d/g, dd );
	s = s.replace( /%Y/g, yyyy );
	return s;
}

function interval_to_seconds ( $interval ) {

        $interval = $interval.replace( /and/, ',' );
        $interval = $interval.replace( /,/, ' ' );

        var $amount = 0;
	var results = $interval.match( /\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/g);  
	for (var i in results) {
		var result = results[i].match( /\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/ );
		if (result[2] == 's') $amount += result[1] ;
		if (result[2] == 'm') $amount += 60 * result[1] ;
		if (result[2] == 'h') $amount += 60 * 60 * result[1] ;
		if (result[2] == 'd') $amount += 60 * 60 * 24 * result[1] ;
		if (result[2] == 'w') $amount += 60 * 60 * 24 * 7 * result[1] ;
		if (result[2] == 'M') $amount += ((60 * 60 * 24 * 365)/12) * result[1] ;
		if (result[2] == 'y') $amount += 60 * 60 * 24 * 365 * result[1] ;
        }
        return $amount;
}

/*
function debug() {
	var s = '';
	for (var i = 0; i < arguments.length; i++) {
		s = s + arguments[i];
	}
	//sdump('D_UTIL','debug:' + s + '\n');
}
*/

function counter_init(id) {
	counter[id] = 0;
}

function counter_incr(id) {
	if (! counter[id]) { counter_init(id); }
	return ++counter[id];
}

function counter_peek(id) {
	if (! counter[id]) { return 0; }
	return counter[id];
}

function timer_init(id) {
	timer[id] = (new Date).getTime();
}

function timer_elapsed(id) {
	if (! timer[id]) { timer_init(id); }
	var ms = (new Date).getTime() - timer[id];
	return( ms + 'ms (' + ms/1000 + 's)' );
}

function dump_ns_node( node ) {
	return (
	'id=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.id.position] 
	+ '>  intra-id=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.intra_doc_id.position]
	+ '>  name=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.name.position]
	+ '>  node_type=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.type.position]
	+ '>  parent_node=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.parent_node.position]
	+ '>  '
	);
}

function nodeset2tree(ns) {
	for (var i in ns) {
		if (ns[i].parent_node) {
			ns_addChild( 
				ns, 
				ns[i].parent_node, 
				ns[i].intra_doc_id 
			);
		}
	}
	return ns;
}

function ns_addChild(ns,p,c) {
	if (! ns[p].children ) { ns[p].children = []; }
	ns[p].children.push(ns[c]);
}

function print_tabs(t) {
	var r = '';
	for (var j = 0; j < t; j++ ) { r = r + "\t"; }
	return r;
}

function pretty_print(s) {
	var r = ''; var t = 0;
	for (var i in s) {
		if (s[i] == '{') {
			r = r + "\n" + print_tabs(t) + s[i]; t++;
			r = r + "\n" + print_tabs(t);
		} else if (s[i] == '[') {
			r = r + "\n" + print_tabs(t) + s[i]; t++;
			r = r + "\n" + print_tabs(t);
		} else if (s[i] == '}') {
			t--; r = r + "\n" + print_tabs(t) + s[i]; 
			r = r + "\n" + print_tabs(t);
		} else if (s[i] == ']') { 
			t--; r = r + "\n" + print_tabs(t) + s[i];
			r = r + "\n" + print_tabs(t);
		} else if (s[i] == ',') {
			r = r + s[i]; 
			r = r + "\n" + print_tabs(t);
		} else {
			r = r + s[i];
		}
	}
	return r;
}

function enable_widgets() {
	for (var i = 0; i < arguments.length; i++) {
		if (typeof(arguments[i]) == 'object') {
			sdump('D_UTIL',arguments[i] + '.disabled = false;\n');
			arguments[i].disabled = false;
		} else {
			var w = document.getElementById( arguments[i] );
			if (w) { 
				sdump('D_UTIL',w + '.disabled = false;\n');
				w.disabled = false; 
			}
		}
	}
}

function disable_widgets() {
	for (var i = 0; i < arguments.length; i++) {
		if (typeof(arguments[i]) == 'object') {
			sdump('D_UTIL',arguments[i] + '.disabled = true;\n');
			arguments[i].disabled = true;
		} else {
			var w = document.getElementById( arguments[i] );
			if (w) { 
				sdump('D_UTIL',w + '.disabled = true;\n');
				w.disabled = true; 
			}
		}
	}
}

function focus_widget(e) {
	if (typeof(e) == 'object') {
		e.focus();
	} else {
		var w = document.getElementById(e);
		if (w) { w.focus(); }
	}
}

function empty_widget(e) {
	if (typeof(e) != 'object') { e = document.getElementById(e); }
	if (typeof(e) != 'object') { sdump('D_UTIL','Failed on empty_widget\n'); return; }
	while (e.lastChild) { e.removeChild(e.lastChild); }
}

function empty_listbox(e) {
	if (typeof(e) != 'object') { e = document.getElementById(e); }
	if (typeof(e) != 'object') { sdump('D_UTIL','Failed on empty_listbox\n'); return; }
	var nl = e.getElementsByTagName('listitem');
	for (var i = 0; i < nl.length; i++) {
		e.removeChild(nl[i]);
	}
}

function swap_attributes(e,a1,a2) {
	if (typeof(e) != 'object') { e = document.getElementById(e); }
	if (typeof(e) != 'object') { sdump('D_UTIL','Failed on swap_attributes\n'); return; }
	var a1_v = e.getAttribute(a1);
	var a2_v = e.getAttribute(a2);
	e.setAttribute(a1,a2_v);
	e.setAttribute(a2, a1_v);
	sdump('D_UTIL','before: a1 = ' + a1_v + ' a2 = ' + a2_v + ' and ');
	sdump('D_UTIL','after: a1 = ' + a2_v + ' a2 = ' + a1_v + '\n');
}

function cycle_attribute(e,a,v) {
	try {
		if (typeof(e) != 'object') { e = document.getElementById(e); }
		if (typeof(e) != 'object') { throw('typeof e != object : typeof e = ' + typeof(e)); }
		if (!a) { throw('!a : a = ' + a); }
		if (! e.getAttribute(a) ) { throw(' ! e.getAttribute(a) : a = ' + a); }
		if (typeof(v) != 'object') { throw('typeof v != object : typeof v = ' + typeof(v)); }

		var toggle = e.getAttribute(a);
		var next_one = false;
		sdump('D_UTIL','cycling ' + a + ' on ' + e.getAttribute('id') + ' to ');
		for (var i = 0; i < v.length; i++) {
			if (next_one) {
				e.setAttribute(a,v[i]);
				sdump('D_UTIL',v[i] + '\n');
				return v[i];
			}
			if (toggle == v[i]) {
				next_one = true;
			}
		}
		if (next_one) {
			e.setAttribute(a,v[0]);
			sdump('D_UTIL',v[0] + '\n');
			return v[0];
		} else {
			throw('current value not in list');
		}
	} catch(E) {
		sdump('D_UTIL','cycle_attribute error: ' + js2JSON(E) + '\n');
		sdump('D_UTIL','null\n');
		return null;
	}
}


function radio_checkbox(ev) {
	var target = ev.target;
	var group = target.getAttribute('group');
	if (group) {
		var nl = document.getElementsByTagName('checkbox');
		for (var i in nl) {
			if (typeof(nl[i])=='object') {
				var c = nl[i];
				var cgroup = c.getAttribute('group');
				if (cgroup == group) {
					c.checked = false;
				}
                        }
                }
		target.checked = true;
	} else {
		sdump('D_UTIL','radio_checkbox: Checkbox must have a group attribute to find peers');
	}
}

function toggle_hidden_grid_rows(grid) {
	if (typeof(grid) != 'object') {
		grid = document.getElementById(grid);
	}
	if (!grid) { return; }
	var rows = grid.lastChild; if (!rows) { return; }
	for (var r = 0; r < rows.childNodes.length; r++ ) {
		var row = rows.childNodes[r];
		if (typeof(row) == 'object') {
			//sdump('D_UTIL','toggle row = ' + row + '\n');
			var hidden = row.getAttribute('hidden');
			if (hidden == 'true') {
				row.setAttribute('hidden','false');
			} else {
				row.setAttribute('hidden','true');
			}
		}
	}
}

/* The first parameter is the id of the element to set, or an array of ids for elements to set in batch.  The second parameter is an object containing the attribute/value pairs to assign to the element or elements */
function xul_setAttributes(el,attrs) {
	if (typeof(el) == 'object') {
		for (var e in el) {
			var w = document.getElementById(e);
			for (var a in attrs) {
				w.setAttribute(a,attrs[a]);
			}
		}
	} else {
		var w = document.getElementById(el);
		for (var a in attrs) {
			w.setAttribute(a,attrs[a]);
		}
	}
}

function append_treeitem() {
	var id = arguments[0];
	var treechildren = document.getElementById(id);
	if (!treechildren) { sdump('D_UTIL','No ' + id + ' to append to\n'); return; }
	var treeitem = document.createElement('treeitem'); treechildren.appendChild(treeitem);
	var treerow = document.createElement('treerow'); treeitem.appendChild(treerow);
	for (var i = 1; i < arguments.length ; i++ ) {
		var treecell = document.createElement('treecell'); treerow.appendChild(treecell);
		treecell.setAttribute('label',arguments[i]);
			treecell.setAttribute('id', 'treeitem_' + treeitem_id + '_' + i);
		//sdump('D_UTIL','treecell.label = ' + arguments[i] + '\n');
	}
	return treeitem_id++;
}

function set_decks(params) {
	for (var deck_id in params) {
		var deck = document.getElementById( deck_id )
		if (deck) deck.setAttribute( 'selectedIndex', params[deck_id] );
	}
}

function super_dump(o,t) {
	var s = "\n";
	for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
	s = s + "=-=-=\n";
	s = s + 'o.constructor == Array = ' + (o.constructor == Array) + '\n';
	for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
	s = s + "typeof = " + typeof(o) + "\n";
	try {
		var string = new XMLSerializer().serializeToString(o);
		return( string + "\n" );
	} catch( E ) {
		var i;
		var c = 0;
		for (i in o) {
			switch(typeof(i)) {
				case 'object':
					s = s + super_dump(i,t+1);
					break;
				default :
					var value = o[i];
					for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
					s = s + "\tMember#" + c++ + "\tType:" + typeof(value);
					if (typeof(value) == 'object') {
						value = super_dump(value,t+1);
					}
					s = s + "\ttoString:" + i.toString() + "\tvalue:" + value + "\n";
					break;
			}
		}
		return( s + "\n" );
	}
}

function super_dump_norecurse(o,t) {
	var s = "\n";
	for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
	s = s + "=-=-=\n";
	s = s + 'o.constructor == Array = ' + (o.constructor == Array) + '\n';
	for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
	s = s + "typeof = " + typeof(o) + "\n";
	try {
		var string = new XMLSerializer().serializeToString(o);
		return( string + "\n" );
	} catch( E ) {
		var i;
		var c = 0;
		for (i in o) {
			switch(typeof(i)) {
				default :
					var value = o[i];
					for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
					s = s + "\tMember#" + c++ + "\tType:" + typeof(value);
					s = s + "\ttoString:" + i.toString() + "\n";
					break;
			}
		}
		return( s + "\n" );
	}
}

function get_my_orgs(user_ou) {

	// self and ancestors
	var current_item_id = user_ou.id();
	//sdump('D_UTIL','mw.G[user_ou] = ' + js2JSON(mw.G['user_ou']) + '\n');
	//sdump('D_UTIL','current_item_id = ' + current_item_id + '\n');
	var item_ou; var my_orgs = {}; var other_orgs = {};
	while( item_ou = find_ou(mw.G['org_tree'],current_item_id) ) {
		//sdump('D_UTIL','\titem_ou = ' + js2JSON(item_ou) + '\n');
		my_orgs[ item_ou.id() ] = item_ou;
		current_item_id = item_ou.parent_ou();
		if (!current_item_id) { break; }
	}

        current_item_id = user_ou.id();
	//sdump('D_UTIL','self & ancestors : my_orgs = <<<'+js2JSON(my_orgs)+'>>>\n');
	// descendants
	var my_children;
        var find_ou_result = find_ou(mw.G['org_tree'],current_item_id);
	if (find_ou_result) { 
		my_children = find_ou_result.children() } 
	else {
		sdump('D_UTIL','ERROR: find_ou(org_tree,'+current_item_id+') returned with no properties\n');
	};
	//sdump('D_UTIL','my_children: ' + my_children + ' : ' + js2JSON(my_children) + '\n');
        if (my_children) {
                for (var i = 0; i < my_children.length; i++) {
                        var my_child = my_children[i];
                        my_orgs[ my_child.id() ] = my_child;
			//sdump('D_UTIL','my_child.children(): ' + my_child.children() + ' : ' + js2JSON(my_child.children()) + '\n');
			if (my_child.children() != null) {
                        	for (var j = 0; j < my_child.children().length; j++) {
					var my_gchild = my_child.children()[j];
					my_orgs[ my_gchild.id() ] = my_gchild;
                        	}
			}
                }
        }
	//sdump('D_UTIL','& descendants : my_orgs = <<<'+js2JSON(my_orgs)+'>>>\n');
	return my_orgs;
}

function get_other_orgs(org,other_orgs) {
}

function flatten_ou_branch(branch) {
	//sdump('D_UTIL','flatten: branch = ' + js2JSON(branch) + '\n');
	var my_array = new Array();
	my_array.push( branch );
	for (var i in branch.children() ) {
		var child = branch.children()[i];
		if (child != null) {
			var temp_array = flatten_ou_branch(child);
			for (var j in temp_array) {
				my_array.push( temp_array[j] );
			}
		}
	}
	return my_array;
}

function find_ou(tree,id) {
	if (typeof(id)=='object') { id = id.id(); }
	if (tree.id()==id) {
		return tree;
	}
	for (var i in tree.children()) {
		var child = tree.children()[i];
		ou = find_ou( child, id );
		if (ou) { return ou; }
	}
	return null;
}

function find_tree_via_children(tree,children_func,find_func) {
	if (typeof(tree)!='object') tree = document.getElementById(tree);

	var t = find_func(tree); if (t) return t;

	var c = children_func(tree);

	for (var i = 0; i < c.length; i++) {
		t = find_func( c[i] );
		if (t) return t;
	}
}

function filter_list(list,f) {
	var new_list = [];
	for (var i in list) {
		var t = f( list[i] );
		if (t) new_list.push( list[i] );
	}
	return new_list;
}

function find_list(list,f) {
	for (var i in list) {
		var t = f( list[i] );
		if (t) return list[i];
	}
	return null;
}

function map_list(list,f) {
	var new_list = [];
	for (var i in list) {
		new_list.push( f( list[i] ) );
	}
	return new_list;
}

function map_object_to_list(obj,f) {
	var new_list = [];
	for (var i in obj) {
		new_list.push( f( obj, i ) );
	}
	return new_list;
}

function convert_object_list_to_hash(list) {
	var my_hash = new Object();
	if (list) {
		for (var i = 0; i < list.length; i++) {
			my_hash[ list[i].id() ] = list[i];
		}
	}
	return my_hash;
}

function find_id_object_in_list(list,id) {
	//sdump('D_UTIL','find_id_object_in_list(' + js2JSON(list).substr(0,20) + '... ,' + id + ')\n');
	if (list) {
		for (var i = 0; i < list.length; i++ ) {
			try {
				if ( list[i].id() == id ) {
					return list[i];
				}
			} catch(E) {
				sdump('D_UTIL','find_id_object_in_list error, i = ' + i + '  typeof(list[i]) = ' + typeof(list[i]) + '  list[i] = ' + js2JSON(list[i]) + ' : ' + js2JSON(E) + '\n');
			}
		}
	}
	//sdump('D_UTIL','not found\n');
	return null;
}

function find_attr_object_in_list(list,attr,value) {
	if (list) {
		for (var i = 0; i < list.length; i++ ) {
			sdump('D_UTIL','find_attr_object_in_list: i = ' + i + '  id = ' + list[i].id() + '\n');
			try {
				var command = 'list[' + i + '].'+attr+'() == ' + value;
				if ( eval(command) ) {
					return list[i];
				}
			} catch(E) {
				sdump('D_UTIL','find_attr_object_in_list error, i = ' + i + '  typeof(list[i]) = ' + typeof(list[i]) + '  list[i] = ' + js2JSON(list[i]) + ' :   list = ' + js2JSON(list) + ' : ' + js2JSON(E) + '\n');
			}
		}
	}
	return null;
}

function find_ou_by_shortname(tree,sn) {
	var ou = new aou();
	if (tree.shortname()==sn) {
		return tree;
	}
	for (var i in tree.children()) {
		var child = tree.children()[i];
		ou = find_ou_by_shortname( child, sn );
		if (ou) { return ou; }
	}
	return null;
}


