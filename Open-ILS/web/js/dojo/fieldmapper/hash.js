/*
# ---------------------------------------------------------------------------
# Copyright (C) 2008  Georgia Public Library Service / Equinox Software, Inc
# Mike Rylander <miker@esilibrary.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------------------
*/

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

	function _toHash (includeNulls, virtFields) {
		var _hash = {};
		for ( var i=0; i < this._fields.length; i++) {
			if (includeNulls || this[this._fields[i]]() != null) {
				if (this[this._fields[i]]() == null)
                    _hash[this._fields[i]] = null;
                else
				    _hash[this._fields[i]] = '' + this[this._fields[i]]();
            }
		}

		if (virtFields && virtFields.length > 0) {
			for (var i in virtFields) {
				if (!_hash[virtFields[i]])
					_hash[virtFields[i]] = null;
			}
		}

		return _hash;
	}

	for (var i in fmclasses) {
		window[i].prototype.fromHash = _fromHash;
		window[i].prototype.toHash = _toHash;
	}

}
