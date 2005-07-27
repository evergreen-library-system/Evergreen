var cn_list;

function copy_edit_init() {
	mw.sdump('D_CAT','entering my_init for copy_edit.js\n');
	mw.sdump('D_CAT','TESTING: copy_edit.js: ' + mw.G['main_test_variable'] + '\n');
	mw.sdump('D_CAT','Gathering copies to put in the acn object...\n');
	var id_mapped_list = [];
	if (params.tree) {
		var list = get_list_from_tree_selection( params.tree );
		mw.sdump('D_CAT','list.length = ' + list.length + '\n');
		var filtered_list = filter_list(
			list,
			function (obj) {
				return (obj.getAttribute('object_type') == 'copy');
			}
		);
		mw.sdump('D_CAT','filtered_list.length = ' + filtered_list.length + '\n');
		id_mapped_list.concat(
			map_list(
				filtered_list,
				function (obj) {
					return obj.getAttribute('copy_id');
				}
			)
		);
		mw.sdump('D_CAT','id_mapped_list.length = ' + id_mapped_list.length + '\n');
	}
	if (params.copy_ids) {
		id_mapped_list = id_mapped_list.concat( copy_ids );
	}
	var result = [];
	try {
		result = user_request(
			'open-ils.search',
			'open-ils.search.asset.copy.fleshed.batch.retrieve', 
			[ id_mapped_list ]
		)[0];
	} catch(E) {
		handle_error(E);
	}
	mw.sdump('D_CAT','result.length = ' + result.length + '\n');
	cn_list = new Array();
	for (var i in result) {
		cn_list[i] = new acn();
		cn_list[i].label( filtered_list[i].getAttribute('callnumber') );
		cn_list[i].owning_lib( filtered_list[i].getAttribute('ou_id') );
		cn_list[i].copies( [ result[i] ] );
	}
	mw.sdump('D_CAT','cn_list = ' + js2JSON(cn_list) + '\n');
	spawn_legacy_copy_editor();
}

function spawn_legacy_copy_editor() {
	mw.sdump('D_CAT','trying to spawn_copy_editor()\n');
	var params = { 'select_all' : true };
	var chrome = 'chrome://evergreen/content/cat/copy.xul';
	var frame = document.getElementById('copy_edit_frame');
	frame.setAttribute('src',chrome);
	frame.setAttribute('flex','1');
	frame.contentWindow.cn_list = cn_list;
	frame.contentWindow.mw = mw;
	frame.contentWindow.real_parentWindow = this;
	frame.contentWindow.parentWindow = window.app_shell;
	frame.contentWindow.params = params;
}

function save_edited_copies() {
	//mw.sdump('D_CAT','trying to save ====================================================================================\n\n\n');
	//mw.sdump('D_CAT','cn_list = ' + js2JSON(cn_list) + '\n\n');
	var copies = [];
	for (var i = 0; i < cn_list.length; i++) {
		var cn_copies = cn_list[i].copies();
		for (var j = 0; j < cn_copies.length; j++) {
			copies.push( cn_copies[j] );
		}
	}
	//mw.sdump('D_CAT','copies = ' + js2JSON(copies) + '\n\n');
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
		mw.sdump('D_CAT','Result = ' + js2JSON(result) + '\n');
		refresh_spawning_browse_list();
	} catch(E) {
		handle_error(E);
	}
}

function refresh_spawning_browse_list() {
	try {
		params.refresh_func();
	} catch(E) {
		mw.sdump('D_CAT','refresh_spawning_browse_list error: ' + js2JSON(E) + '\n');
	}
}
