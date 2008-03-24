
function _fromStoreItem (data) {
	this.fromHash(data);

	var _fields = fmclasses[this.classname];
	for ( var i=0; i < _fields.length; i++) {
		if (dojo.isArray( this[_fields[i]]() ))
			this[_fields[i]]( this[_fields[i]]()[0] );
	}
	return this;
}

for (var i in fmclasses) window[i].prototype.fromStoreItem = _fromStoreItem;

