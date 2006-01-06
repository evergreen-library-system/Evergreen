function is_true(item) {
	return !is_false(item);
}

function is_false(item) { 
	if( ! item ) return true;
	if( item.match(/0/) ) return true;
	false;
}
