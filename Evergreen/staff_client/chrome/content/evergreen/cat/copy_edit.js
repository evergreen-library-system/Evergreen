var cn_list;

function copy_edit_init() {
	dump('entering my_init for copy_edit.js\n');
	dump('TESTING: copy_edit.js: ' + mw.G['main_test_variable'] + '\n');
	dump('Gathering copies to put in the acn object...\n');
	var list = get_list_from_tree_selection( params.tree );
	dump('list.length = ' + list.length + '\n');
	var filtered_list = filter_list(
		list,
		function (obj) {
			return (obj.getAttribute('object_type') == 'copy');
		}
	);
	dump('filtered_list.length = ' + filtered_list.length + '\n');
	var id_mapped_list  = map_list(
		filtered_list,
		function (obj) {
			return obj.getAttribute('copy_id');
		}
	);
	dump('id_mapped_list.length = ' + id_mapped_list.length + '\n');
	var result = user_request(
		'open-ils.search',
		'open-ils.search.asset.copy.fleshed.batch.retrieve', 
		[ id_mapped_list ]
	)[0];
	dump('result.length = ' + result.length + '\n');
	cn_list = new Array();
	for (var i in result) {
		cn_list[i] = new acn();
		cn_list[i].label( filtered_list[i].getAttribute('callnumber') );
		cn_list[i].owning_lib( filtered_list[i].getAttribute('ou_id') );
		cn_list[i].copies( [ result[i] ] );
	}
	dump('cn_list = ' + js2JSON(cn_list) + '\n');
	spawn_copy_editor();
}

function spawn_copy_editor() {
	dump('trying to spawn_copy_editor()\n');
	var params = { 'select_all' : false };
	var chrome = 'chrome://evergreen/content/cat/copy.xul';
	var frame = document.getElementById('copy_edit_frame');
	frame.setAttribute('src',chrome);
	frame.setAttribute('flex','1');
	frame.contentWindow.cn_list = cn_list;
	frame.contentWindow.mw = mw;
	frame.contentWindow.real_parentWindow = this;
	frame.contentWindow.parentWindow = parentWindow;
	frame.contentWindow.params = params;
}

function save_edited_copies() {
	//dump('trying to save ====================================================================================\n\n\n');
	//dump('cn_list = ' + js2JSON(cn_list) + '\n\n');
	var copies = [];
	for (var i = 0; i < cn_list.length; i++) {
		var cn_copies = cn_list[i].copies();
		for (var j = 0; j < cn_copies.length; j++) {
			copies.push( cn_copies[j] );
		}
	}
	//dump('copies = ' + js2JSON(copies) + '\n\n');
	try {
		var result = user_request(
			'open-ils.cat',
			'open-ils.cat.asset.copy.fleshed.batch.update',
			[ mw.G.auth_ses[0], copies ]
		)[0];
		if (result == '1') {
			alert('Successfully updated these copies.\n');
		} else {
			throw('There was an error updating the copies.\n');
		}
		dump('Result = ' + js2JSON(result) + '\n');
		refresh_spawning_browse_list();
	} catch(E) {
		handle_error(E);
	}
}

function refresh_spawning_browse_list() {
	try {
		params.refresh_func();
	} catch(E) {
		dump('refresh_spawning_browse_list error: ' + js2JSON(E) + '\n');
	}
}
