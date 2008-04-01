
function _toHash () {
	var _hash = {};
	var _fields = fmclasses[this.classname];
	for ( var i=0; i < _fields.length; i++) {
		if (this[_fields[i]]() != null)
			_hash[_fields[i]] = '' + this[_fields[i]]();
	}
	return _hash;
}

for (var i in fmclasses) window[i].prototype.toHash = _toHash;

