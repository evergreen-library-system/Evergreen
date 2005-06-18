sdump('D_TRACE','Loading explode.js\n');
var EXPLODE = {};

function explode_aou(id) {
	return find_ou( mw.G.org_tree, id );
}
EXPLODE.aou = explode_aou;
EXPLODE.au_homelib = explode_aou;

function explode_ap(id) {
	//return find_id_object_in_list( mw.G.ap_list, id );
	return mw.G.ap_hash[ id ];
}
EXPLODE.ap = explode_ap;
EXPLODE.au_profile = explode_ap;

function magic_field_edit( ev, otype, o_id, field, explode ) {
	sdump('D_TRACE','\nIn magic_field_edit\n')
	var target = ev.target;
	sdump('D_EXPLODE','\ttarget = ' + target + '\n');
	sdump('D_EXPLODE','\totype = ' + otype + '\n');
	sdump('D_EXPLODE','\tfield = ' + field + '\n');
	var value = target.value;
	sdump('D_EXPLODE','\tvalue = ' + value + '\n');
	sdump('D_EXPLODE','\texplode = ' + explode + '\n');
	try {
		if (explode) {
			var command = ( 'value = EXPLODE.' + otype + '_' + field + '(' + value + ');' );
			sdump('D_EXPLODE','\tcommand = ' + command + '\n');
			eval( command );
		}
	} catch(E) {
		sdump('D_EXPLODE', '\tNo EXPLODE.' + otype + '_' + field + '() defined\n' );
	}
	sdump('D_EXPLODE','\tvalue = ' + value + '\n');
	sdump('D_EXPLODE','\t' + otype + '_id = ' + o_id + '\n');
	// ######## method 1, node in element
	var row = document.getElementById( otype + o_id );
	if (row) {
		var node = JSON2js(row.getAttribute('node'));
		sdump('D_EXPLODE','\telem: original node = ' + js2JSON(node) + '\n');
		var command = ( 'node.' + field + '(' + js2JSON(value) + ');');
		eval(command);
		var command2 = ( 'node.ischanged("1");');
		eval(command2);
		sdump('D_EXPLODE','\telem:    after edit = ' + js2JSON(node) + '\n');
		row.setAttribute('node',js2JSON(node));
	} else {
		sdump('D_EXPLODE','\tCould not find containing element with id = ' + otype + o_id + '\n');
	}
	// ######## method 2, node in hash
	try {
		var myhash = eval('hash_'+otype);
		if (typeof(myhash) == 'object') {
			if (! myhash[o_id] ) { myhash[o_id] = eval('new ' + otype + '();'); }
			sdump('D_EXPLODE','\thash: original node = ' + js2JSON(myhash[o_id]) + '\n');
			var command = ('myhash[o_id].' + field + '(' + js2JSON(value) + ');');
			eval(command);
			var command2 = ( 'myhash[o_id].ischanged("1");');
			eval(command2);
			sdump('D_EXPLODE','\thash:    after edit = ' + js2JSON(myhash[o_id]) + '\n');
		}
	} catch(E) {
		sdump('D_EXPLODE','magic_field_edit: ' + js2JSON(E) + '\n');
	}
}

