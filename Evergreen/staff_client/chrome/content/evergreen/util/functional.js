sdump('D_FUNCTIONAL',"Loading functional.js\n");

function filter_list(list,f) {
	var new_list = [];
	for (var i in list) {
		var t = f( list[i] );
		if (t) new_list.push( list[i] );
	}
	return new_list;
}

function filter_object(obj,f) {
	var new_obj = {};
	for (var i in obj) {
		var t = f( i, obj[i] );
		if (t) new_obj[i] = obj[i];
	}
	return new_obj;
}

function find_list(list,f) {
	for (var i in list) {
		var t = f( list[i] );
		if (t) return list[i];
	}
	return null;
}

function find_object(obj,f) {
	for (var i in obj) {
		var t = f( i, obj[i] );
		if (t) return obj[i];
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

function map_flat_list(list,f) {
	var new_list = [];
	for (var i in list) {
		new_list = new_list.concat( f( list[i] ) );
	}
	return new_list;
}

function map_object(obj,f) {
	var new_obj = {};
	for (var i in obj) {
		new_obj[ f( i, obj[i] )[0] ] = f( i, obj[i] )[1];
	}
	return new_obj;
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
	//sdump('D_FUNCTIONAL','find_id_object_in_list(' + js2JSON(list).substr(0,20) + '... ,' + id + ')\n');
	if (list) {
		for (var i = 0; i < list.length; i++ ) {
			try {
				if ( list[i].id() == id ) {
					return list[i];
				}
			} catch(E) {
				sdump('D_FUNCTIONAL','find_id_object_in_list error, i = ' + i + '  typeof(list[i]) = ' + typeof(list[i]) + '  list[i] = ' + js2JSON(list[i]) + ' : ' + js2JSON(E) + '\n');
			}
		}
	}
	//sdump('D_FUNCTIONAL','not found\n');
	return null;
}

function find_attr_object_in_list(list,attr,value) {
	if (list) {
		for (var i = 0; i < list.length; i++ ) {
			sdump('D_FUNCTIONAL','find_attr_object_in_list: i = ' + i + '  id = ' + list[i].id() + '\n');
			try {
				var command = 'list[' + i + '].'+attr+'() == ' + value;
				if ( eval(command) ) {
					return list[i];
				}
			} catch(E) {
				sdump('D_FUNCTIONAL','find_attr_object_in_list error, i = ' + i + '  typeof(list[i]) = ' + typeof(list[i]) + '  list[i] = ' + js2JSON(list[i]) + ' :   list = ' + js2JSON(list) + ' : ' + js2JSON(E) + '\n');
			}
		}
	}
	return null;
}


