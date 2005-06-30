sdump('D_WIDGETS',"Loading widgets.js\n");

// This was originally used in circ.js for checkin and checkout lists.
// The first argument is the treechildren element for the tree.
// Subsequent arguments are treated as textual values for treecells in that treeitem.
var treeitem_id = 0;
function append_treeitem(d,e) {
	if (typeof(e) != 'object') { e = d.getElementById(e); }
	if (typeof(e) != 'object') { throw('typeof e != object : typeof e = ' + typeof(e)); }
	var treechildren = e;

	if (!treechildren) { sdump('D_WIDGETS','No ' + id + ' to append to\n'); return; }

	var treeitem = elem('treeitem'); treechildren.appendChild(treeitem);
	var treerow = elem('treerow'); treeitem.appendChild(treerow);
	for (var i = 2; i < arguments.length ; i++ ) {
		var treecell = elem(
			'treecell',
			{ 'label': arguments[i], 'id' : 'treeitem_' + treeitem_id + '_' + i }
		);
		treerow.appendChild(treecell);
		//sdump('D_WIDGETS','treecell.label = ' + arguments[i] + '\n');
	}
	return treeitem_id++;
}

// This was used in browse_list.js as a more flexible alternative to swap_attribute.
// The first argument is the element, the second argument is the pertinant attribute,
// and the third argument is an array of values to cycle through for setting the
// element's attribute.  Ex: var toggle = cycle_attribute( target,'toggle',['1','2','3'] );
function cycle_attribute(d,e,a,v) {
	try {
		if (typeof(e) != 'object') { e = d.getElementById(e); }
		if (typeof(e) != 'object') { throw('typeof e != object : typeof e = ' + typeof(e)); }
		if (!a) { throw('!a : a = ' + a); }
		if (! e.getAttribute(a) ) { throw(' ! e.getAttribute(a) : a = ' + a); }
		if (typeof(v) != 'object') { throw('typeof v != object : typeof v = ' + typeof(v)); }

		var toggle = e.getAttribute(a);
		var next_one = false;
		sdump('D_WIDGETS','cycling ' + a + ' on ' + e.getAttribute('id') + ' to ');
		for (var i = 0; i < v.length; i++) {
			if (next_one) {
				e.setAttribute(a,v[i]);
				sdump('D_WIDGETS',v[i] + '\n');
				return v[i];
			}
			if (toggle == v[i]) {
				next_one = true;
			}
		}
		if (next_one) {
			e.setAttribute(a,v[0]);
			sdump('D_WIDGETS',v[0] + '\n');
			return v[0];
		} else {
			throw('current value not in list');
		}
	} catch(E) {
		sdump('D_WIDGETS','cycle_attribute error: ' + js2JSON(E) + '\n');
		sdump('D_WIDGETS','null\n');
		return null;
	}
}

// Treats each argument as an element to disable 
function disable_widgets(d) {
	for (var i = 1; i < arguments.length; i++) {
		if (typeof(arguments[i]) == 'object') {
			sdump('D_WIDGETS',arguments[i] + '.disabled = true;\n');
			arguments[i].disabled = true;
		} else {
			var w = d.getElementById( arguments[i] );
			if (w) { 
				sdump('D_WIDGETS',w + '.disabled = true;\n');
				w.disabled = true; 
			}
		}
	}
}

// removes listitems from listboxes
function empty_listbox(d,e) {
	if (typeof(e) != 'object') { e = d.getElementById(e); }
	if (typeof(e) != 'object') { sdump('D_WIDGETS','Failed on empty_listbox\n'); return; }
	var nl = e.getElementsByTagName('listitem');
	for (var i = 0; i < nl.length; i++) {
		e.removeChild(nl[i]);
	}
}

// removes all of an element's children
function empty_widget(d,e) {
	if (typeof(e) != 'object') { e = d.getElementById(e); }
	if (typeof(e) != 'object') { sdump('D_WIDGETS','Failed on empty_widget\n'); return; }
	while (e.lastChild) { e.removeChild(e.lastChild); }
}


// Treats each argument as an element to enable 
function enable_widgets(d) {
	for (var i = 1; i < arguments.length; i++) {
		if (typeof(arguments[i]) == 'object') {
			sdump('D_WIDGETS',arguments[i] + '.disabled = false;\n');
			arguments[i].disabled = false;
		} else {
			var w = d.getElementById( arguments[i] );
			if (w) { 
				sdump('D_WIDGETS',w + '.disabled = false;\n');
				w.disabled = false; 
			}
		}
	}
}

// Originally used in volume.js after intercepting Enter presses on the keyboard.
// The first argument is the element to search for textboxes, and the second
// argument is the current textbox.  This function finds the next textbox and
// gives it focus.
function fake_tab_for_textboxes(d,w,current) {
	var flag = false; var next_one;
	if (typeof(w)!='object') {
		w = d.getElementById(w);
	}
	sdump('D_WIDGETS', 'fake_tab_for_textboxes: Current ' + current + '\n');
	var nl = w.getElementsByTagName('textbox');
	//var nl = d.getElementsByTagName('textbox');
	sdump('D_WIDGETS', 'fake_tab_for_textboxes: nl.length = ' + nl.length + '\n');
	for (var i = 0; i < nl.length; i++) {
		sdump('D_WIDGETS', 'fake_tab_for_textboxes: Considering ' + nl[i] + '...\n');
		if (flag && !next_one) {
			sdump('D_WIDGETS', 'fake_tab_for_textboxes: Setting next_one ' + nl[i] + '\n');	
			next_one = nl[i];
		}
		if (nl[i] === current) {
			sdump('D_WIDGETS','fake_tab_for_textboxes: Found current\n');
			flag = true;
		}
	}
	if (!next_one) {
		sdump('D_WIDGETS','fake_tab_for_textboxes: Out of loop, Setting next_one ' + nl[0] + '\n');	
		next_one = nl[0];
	}
	if (next_one) {
		next_one.focus(); next_one.select();
	} else {
		sdump('D_WIDGETS','fake_tab_for_textboxes: next_one not set\n');
	}
}


// Not actually used anywhere.  I'm not sure what this is :D
// Ah, looks like it could handle XUL trees and fieldmapper trees
// Ex. find( org_tree, function(o){return o.children();}, function(o){return (o.id == 'the winner');})
function find_tree_via_children(d,tree,children_func,find_func) {
	if (typeof(tree)!='object') tree = d.getElementById(tree);

	var t = find_func(tree); if (t) return t;

	var c = children_func(tree);

	for (var i = 0; i < c.length; i++) {
		t = find_func( c[i] );
		if (t) return t;
	}
}


// Give this element focus
function focus_widget(d,e) {
	if (typeof(e) == 'object') {
		e.focus();
	} else {
		var w = d.getElementById(e);
		if (w) { w.focus(); }
	}
}

// Returns a list of selected treeitems from the specified tree
function get_list_from_tree_selection(d,tree_w) {
	sdump('D_WIDGETS','entering get_list_from_tree...\n');
	var hitlist;
	if (typeof(tree_w) != 'object') {
		hitlist = d.getElementById(tree_w);
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
			//sdump('D_WIDGETS',i.tagName + '\n');
			list.push( i );
		}
	}
	sdump('D_WIDGETS','leaving get_list_from_tree...\n');
	return list;
}

// Make sure we a widget
function get_widget(d,e) {
	if (typeof(e) == 'object') {
		return e;
	} else {
		var w = d.getElementById(e);
		if (w) return w;
	}
	return null;
}

// Increment a XUL progressmeter
function incr_progressmeter(d,meter,increment) {
	if (typeof(meter)!='object') 
		meter = d.getElementById(meter);
	if (typeof(meter)!='object')
		return;

	var real = meter.getAttribute('_real');

	if (!real)
		real = 0;
	real = parseFloat( real ) + parseFloat( increment );

	if (real > 100)
		real = 100;
	else if ( real < 0)
		real = 0;

	meter.setAttribute('_real',real);
	meter.value = Math.ceil( real );
}

// Simulates radio buttons with checkboxes.  Include this in command event listeners
// for the pertinent textboxes.  For any set of checkboxes that have the same 'group'
// attribute, only one can be checked at a time.
function radio_checkbox(d,ev) {
	var target = ev.target;
	var group = target.getAttribute('group');
	if (group) {
		var nl = d.getElementsByTagName('checkbox');
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
		sdump('D_WIDGETS','radio_checkbox: Checkbox must have a group attribute to find peers');
	}
}

// simpler version of set_decks
function set_deck(d,deck,idx) {
	set_decks(d,{ deck : idx });
}

// Takes a hash with key:value => deck element id : page index
// Sets each deck to the corresponding index
function set_decks(d,params) {
	for (var deck_id in params) {
		var deck;
		if (typeof(deck) != 'object')
			deck = d.getElementById( deck_id )
		if (deck) deck.setAttribute( 'selectedIndex', params[deck_id] );
	}
}

// swaps the values of two attributes for an element
function swap_attributes(d,e,a1,a2) {
	if (typeof(e) != 'object') { e = d.getElementById(e); }
	if (typeof(e) != 'object') { sdump('D_WIDGETS','Failed on swap_attributes\n'); return; }
	var a1_v = e.getAttribute(a1);
	var a2_v = e.getAttribute(a2);
	e.setAttribute(a1,a2_v);
	e.setAttribute(a2, a1_v);
	sdump('D_WIDGETS','before: a1 = ' + a1_v + ' a2 = ' + a2_v + ' and ');
	sdump('D_WIDGETS','after: a1 = ' + a2_v + ' a2 = ' + a1_v + '\n');
}

// Flips the hidden value for each row in a grid
function toggle_hidden_grid_rows(d,grid) {
	if (typeof(grid) != 'object') {
		grid = d.getElementById(grid);
	}
	if (!grid) { return; }
	var rows = grid.lastChild; if (!rows) { return; }
	for (var r = 0; r < rows.childNodes.length; r++ ) {
		var row = rows.childNodes[r];
		if (typeof(row) == 'object') {
			//sdump('D_WIDGETS','toggle row = ' + row + '\n');
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
function xul_setAttributes(d,el,attrs) {
	if (typeof(el) == 'object') {
		for (var e in el) {
			var w = d.getElementById(e);
			for (var a in attrs) {
				w.setAttribute(a,attrs[a]);
			}
		}
	} else {
		var w = d.getElementById(el);
		for (var a in attrs) {
			w.setAttribute(a,attrs[a]);
		}
	}
}

