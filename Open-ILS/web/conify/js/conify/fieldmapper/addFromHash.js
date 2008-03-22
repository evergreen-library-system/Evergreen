
function _fromHash (_hash) {
	var _fields = fmclasses[this.classname];
	for ( var i=0; i < _fields.length; i++) {
		if (_hash[_fields[i]] != null)
			this[_fields[i]]( _hash[_fields[i]] );
	}
	return this;
}

for (var i in fmclasses) window[i].prototype.fromHash = _fromHash;

