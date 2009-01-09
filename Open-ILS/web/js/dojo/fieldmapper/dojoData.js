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

if(!dojo._hasResource['fieldmapper.dojoData']){

	dojo._hasResource['fieldmapper.dojoData'] = true;
	dojo.provide('fieldmapper.dojoData');
	dojo.require('fieldmapper.Fieldmapper');
	dojo.require('fieldmapper.hash');


	function _fromStoreItem (data) {
		this.fromHash(data);

		for (var i in this._ignore_fields)
			this[this._ignore_fields[i]](null);

		for ( var i=0; i < this._fields.length; i++) {
			if (dojo.isArray( this[this._fields[i]]() ))
				this[this._fields[i]]( this[this._fields[i]]()[0] );
		}
		return this;
	}

    function _initStoreData(label, params) {
		if (!params) params = {};
		if (!params.identifier) params.identifier = this.Identifier;
		if (!label) label = params.label;
		if (!label) label = params.identifier;
		return { label : label, identifier : params.identifier, items : [] };
    }

    function _toStoreItem(fmObj, params) {
		if (!params) params = {};
        return fmObj.toHash(true, params.virtualFields);
    }

	function _toStoreData (list, label, params) {
		if (!params) params = {};
        var data = this.initStoreData(label, params);

		for (var i in list) data.items.push( list[i].toHash(true, params.virtualFields) );

		if (params.children && params.parent) {
			var _hash_list = data.items;

			var _find_root = {};
			for (var i in _hash_list) {
				_find_root[_hash_list[i][params.identifier]] = _hash_list[i]; 
			}

			var item_data = [];
			for (var i in _hash_list) {
				var obj = _hash_list[i]
				obj[params.children] = [];

				for (var j in _hash_list) {
					var kid = _hash_list[j];
					if (kid[params.parent] == obj[params.identifier]) {
						obj[params.children].push( { _reference : kid[params.identifier] } );
						kid._iskid = true;
						if (_find_root[kid[params.identifier]]) delete _find_root[kid[params.identifier]];
					}
				}

				item_data.push( obj );
			}

			for (var j in _find_root) {
				_find_root[j]['_top'] = 'true';
				if (!_find_root[j][params.parent])
					_find_root[j]['_trueRoot'] = 'true';
			}

			data.items = item_data;
		}

		return data;
	}

	for (var i in fmclasses) fieldmapper[i].prototype.fromStoreItem = _fromStoreItem;
	for (var i in fmclasses) fieldmapper[i].toStoreData = _toStoreData;
	for (var i in fmclasses) fieldmapper[i].toStoreItem = _toStoreItem;
	for (var i in fmclasses) fieldmapper[i].prototype.toStoreItem = function ( args ) { return _toStoreItem(this, args) };
	for (var i in fmclasses) fieldmapper[i].initStoreData = _initStoreData;

	fieldmapper.aou.prototype._ignore_fields = ['children'];
	fieldmapper.aout.prototype._ignore_fields = ['children'];
	fieldmapper.pgt.prototype._ignore_fields = ['children'];

	fieldmapper.aou.toStoreData = function (list, label) {
		if (!label) label = 'shortname';
		return _toStoreData.call(this, list, label, { 'parent' : 'parent_ou', 'children' : 'children' });
	}

	fieldmapper.aout.toStoreData = function (list, label) {
		if (!label) label = 'name';
		return _toStoreData.call(this, list, label, { 'parent' : 'parent', 'children' : 'children' });
	}

	fieldmapper.pgt.toStoreData = function (list, label) {
		if (!label) label = 'name';
		return _toStoreData.call(this, list, label, { 'parent' : 'parent', 'children' : 'children' });
	}

	/*
	ppl.toStoreData = function (list, label) {
		if (!label) label = 'code';
		return _toStoreData(list, label, {});
	}
	*/

}
