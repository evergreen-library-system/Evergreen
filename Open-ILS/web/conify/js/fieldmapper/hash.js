if(!dojo._hasResource['fieldmapper.hash']){

	dojo._hasResource['fieldmapper.hash'] = true;
	dojo.provide('fieldmapper.hash');
	dojo.require('fieldmapper.Fieldmapper');

	function _fromHash (_hash) {
		var _fields = fmclasses[this.classname];
		for ( var i=0; i < _fields.length; i++) {
			if (_hash[_fields[i]] != null)
				this[_fields[i]]( _hash[_fields[i]] );
		}
		return this;
	}

	for (var i in fmclasses) {
		window[i].prototype.fromHash = _fromHash;
		window[i].prototype.toHash = _toHash;
	}


	function _toHash () {
		var _hash = {};
		var _fields = fmclasses[this.classname];
		for ( var i=0; i < _fields.length; i++) {
			if (this[_fields[i]]() != null)
				_hash[_fields[i]] = '' + this[_fields[i]]();
		}
		return _hash;
	}


}
