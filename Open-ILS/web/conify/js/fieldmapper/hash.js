if(!dojo._hasResource['fieldmapper.hash']){

	dojo._hasResource['fieldmapper.hash'] = true;
	dojo.provide('fieldmapper.hash');
	dojo.require('fieldmapper.Fieldmapper');

	function _fromHash (_hash) {
		for ( var i=0; i < this._fields.length; i++) {
			if (_hash[this._fields[i]] != null)
				this[this._fields[i]]( _hash[this._fields[i]] );
		}
		return this;
	}

	function _toHash () {
		var _hash = {};
		for ( var i=0; i < this._fields.length; i++) {
			if (this[this._fields[i]]() != null)
				_hash[this._fields[i]] = '' + this[this._fields[i]]();
		}
		return _hash;
	}

	for (var i in fmclasses) {
		window[i].prototype.fromHash = _fromHash;
		window[i].prototype.toHash = _toHash;
	}

}
