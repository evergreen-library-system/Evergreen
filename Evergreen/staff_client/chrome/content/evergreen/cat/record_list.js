dump('Parsing record_list.js\n');

var test_hash = { 'a' : '123' } ;

function my_init() {
	timer_init('cat');
	dump('TESTING: record_list.js: ' + mw.G['main_test_variable'] + '\n');
	dump('test_hash = ' + js2JSON(test_hash) + '\n');
	dump('search_term = ' + search_term + '  search_type = ' + search_type + '  search_order = ' + search_order + '  search_location = ' + search_location + '\n');
	var b = document.getElementById('count_copy_toggle');
	b.setAttribute('label','Click to Show Records for All Libraries');
	b.setAttribute('alt_label','Click to Show Only Records with Copies at ' + find_ou(mw.G['org_tree'],search_location).name());
	b.setAttribute('value','-1');
	b.setAttribute('oncommand','toggle_view(event);');

	search();
}

function toggle_view(ev) {
	var b = ev.target;
	var value = b.getAttribute('value');
	var label = b.getAttribute('label');
	var alt_label = b.getAttribute('alt_label');
	var temp = label; label = alt_label; alt_label = temp;
	b.setAttribute('label',label); b.setAttribute('alt_label',alt_label);
	b.setAttribute('value',-value);
	var rows = document.getElementById('record_list_tree_children');
	var nl = rows.getElementsByTagName('treeitem');
	for (var i in nl) {
		if (typeof(nl[i])=='object') {
			var treeitem = nl[i];
			var treerow = treeitem.firstChild;
			var copy_count_cell = treerow.lastChild;
			var copy_count = copy_count_cell.getAttribute('label');
			if (value == '-1') {
				treeitem.setAttribute('hidden','false');
			} else {
				if (copy_count == '0') {
					treeitem.setAttribute('hidden','true');
				}
			}
		}
	}
}

function search() {
	var result;
	dump('search_type = ' + search_type + '  search_order = ' + search_order + '  search_term = ' + search_term + '\n');
	switch(search_type) {
		case 'tcn':
			result = user_request(
				'open-ils.search',
				'open-ils.search.cat.biblio.tcn',
				[ search_term ]
			);
			break;
		default:
			result = user_request(
				'open-ils.search',
				'open-ils.search.cat.biblio.class',
				[ search_location, search_type, search_order, search_term ]
			);
			break;
	}
	// populate record_list with results
	//dump( js2JSON( result ) + '\n');
	var tc = document.getElementById('record_list_tree_children');
	for (var i in result) {
		if (typeof(result[i])=='object') {
			var data = result[i];
			var item = make_treeitem(data['doc_id']);
			var row = make_treerow(
				data['title'],
				data['author'],
				data['tcn'],
				data['publisher'],
				data['pubdate'],
				data['isbn'],
				data['isbn'],
				data['copy_count']
			);
			if (data['copy_count'] == 0) {
				item.setAttribute('hidden','true');
			}
			item.appendChild( row );
			tc.appendChild( item );
		} else {
			//dump('unexpected typeof(result['+i+']) = ' + typeof(result[i]) + ' : ' + result[i] + '\n');
		}
	}
}

function make_treeitem(owner_doc) {
	var treeitem = document.createElement('treeitem');
	treeitem.setAttribute('id',owner_doc);
	//dump('treeitem = ' + treeitem + '\n');
	return treeitem;
}

function make_treerow() {
	var treerow = document.createElement('treerow');
	//dump('treerow = ' + treerow + '\n');
	//dump('arguments.length = ' + arguments.length + ' arguments = ' + js2JSON(arguments) + '\n');
	for (var i = 0; i < arguments.length; i++) {
		//dump(i + ' : ' + arguments[i] + '\n');
		var treecell = document.createElement('treecell');
		//dump('treecell = ' + treecell + '\n');
		var text = '';
		if (typeof(arguments[i])=='object') {
			for (var j in arguments[i]) {
				text = text + arguments[i][j] + ' / ';
			}
		} else {
			text = arguments[i];
		}
		treecell.setAttribute('label',text);
		treerow.appendChild(treecell);
	}
	return treerow;
}

function spawn_editors(tab) {
	var hitlist = document.getElementById('record_list_tree');
	var start = new Object();
	var end = new Object();
	var numRanges = hitlist.view.selection.getRangeCount();
	for (var t=0; t<numRanges; t++){
		hitlist.view.selection.getRangeAt(t,start,end);
		for (var v=start.value; v<=end.value; v++){
			var i = hitlist.contentView.getItemAtIndex(v);
			dump(i.tagName + '\n');
			var params = [
				i.getAttribute('id'),
				i.firstChild.childNodes[0].getAttribute('label'),
				i.firstChild.childNodes[1].getAttribute('label'),
				i.firstChild.childNodes[2].getAttribute('label'),
				i.firstChild.childNodes[3].getAttribute('label'),
				i.firstChild.childNodes[4].getAttribute('label'),
				i.firstChild.childNodes[5].getAttribute('label'),
				i.firstChild.childNodes[6].getAttribute('label')
			];
			spawn_marc_editor(tab,params);
		}
	}
}

function spawn_browsers(tab) {
	var hitlist = document.getElementById('record_list_tree');
	var start = new Object();
	var end = new Object();
	var numRanges = hitlist.view.selection.getRangeCount();
	for (var t=0; t<numRanges; t++){
		hitlist.view.selection.getRangeAt(t,start,end);
		for (var v=start.value; v<=end.value; v++){
			var i = hitlist.contentView.getItemAtIndex(v);
			dump(i.tagName + '\n');
			var params = [ i.getAttribute('id') ];
			spawn_copy_browser(tab,params);
		}
	}
}

/*
function spawn_copy_browser(tab,params) {
	dump('trying to spawn_marc_editor('+params[0]+')\n');
	var w;
	var chrome = 'chrome://evergreen/content/cat/browse_list.xul';
	if (tab) {
		tabWindow.new_tab('main_tabbox');
		w = tabWindow.replace_tab('main_tabbox','COPIES',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	w.find_this_id = params[0];
	w.record_columns = params;
}


function spawn_marc_editor(tab,params) {
	dump('trying to spawn_marc_editor('+params[0]+')\n');
	var w;
	var chrome = 'chrome://evergreen/content/cat/marc.xul';
	if (tab) {
		tabWindow.new_tab('main_tabbox');
		w = tabWindow.replace_tab('main_tabbox','MARC',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	w.find_this_id = params[0];
	w.record_columns = params;
}
*/

