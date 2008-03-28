
function _fromStoreItem (data) {
	this.fromHash(data);

	for (var i in this._ignore_fields)
		this[this._ignore_fields[i]](null);

	var _fields = fmclasses[this.classname];
	for ( var i=0; i < _fields.length; i++) {
		if (dojo.isArray( this[_fields[i]]() ))
			this[_fields[i]]( this[_fields[i]]()[0] );
	}
	return this;
}

for (var i in fmclasses) window[i].prototype.fromStoreItem = _fromStoreItem;

aou.prototype._ignore_fields = ['children'];
aout.prototype._ignore_fields = ['children'];
pgt.prototype._ignore_fields = ['children'];
