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

if(!dojo._hasResource["fieldmapper.Fieldmapper"]){
    dojo._hasResource["fieldmapper.Fieldmapper"] = true;

    dojo.provide("fieldmapper.Fieldmapper");
    dojo.require("DojoSRF");


/* generate fieldmapper javascript classes.  This expects a global variable
    called 'fmclasses' to be fleshed with the classes we need to build */

    function FMEX(message) { this.message = message; }
    FMEX.toString = function() { return "FieldmapperException: " + this.message + "\n"; };

    dojo.declare( "fieldmapper.Fieldmapper", null, {

        constructor : function (initArray) {
            if (initArray) {
                if (dojo.isArray(initArray)) {
                    this.a = initArray;
                } else {
                    this.a = [];
                }
            }
        },

        _isfieldmapper : true,

        clone : function() {
            var obj = new this.constructor();

            for( var i in this.a ) {
                var thing = this.a[i];
                if(thing === null) continue;

                if( thing._isfieldmapper ) {
                    obj.a[i] = thing.clone();
                } else {

                    if(dojo.isArray(thing)) {
                        obj.a[i] = [];

                        for( var j in thing ) {

                            if( thing[j]._isfieldmapper )
                                obj.a[i][j] = thing[j].clone();
                            else
                                obj.a[i][j] = thing[j];
                        }
                    } else {
                        obj.a[i] = thing;
                    }
                }
            }
            return obj;
        },

        RequiredField : function (f) {
            if (!f) return;
            if (fieldmapper.IDL && fieldmapper.IDL.loaded)
                return this.Structure.fields[f].required;
            return;
        },

        ValidateField : function (f) {
            if (!f) return;
            if (fieldmapper.IDL && fieldmapper.IDL.loaded) {
                if (this.Structure.fields[f] && this.Structure.fields[f].validate) {
                    return this.Structure.fields[f].validate.test(this[f]());
                }
                return true;
            }
            return;
        },

        toString : function() {
            /* ever so slightly aid debugging */
            if (this.classname)
                return "[object fieldmapper." + this.classname + "]";
            else
                return Object.prototype.toString();
        }

    });


    fieldmapper.vivicateClass = function (cl) {
        dojo.provide( cl );
        dojo.declare( cl , fieldmapper.Fieldmapper, {
            constructor : function () {
                if (!this.a) this.a = [];
                this.classname = this.declaredClass;
                this._fields = [];

                var p, f;
                if (fieldmapper.IDL && fieldmapper.IDL.loaded) {
                    this.Structure = fieldmapper.IDL.fmclasses[this.classname];

                    var array_pos = 0;
                    for (f in fieldmapper.IDL.fmclasses[this.classname].fields) {
                        var field = fieldmapper.IDL.fmclasses[this.classname].fields[f];
                        p = array_pos++;
                        this._fields.push( field.name );
                        this[field.name]=new Function('n', 'if(arguments.length==1)this.a['+p+']=n;return this.a['+p+'];');
                    }
                } else {
                    this._fields = fmclasses[this.classname];

                    for( var pos = 0; pos <  this._fields.length; pos++ ) {
                        p = parseInt(pos, 10);
                        f = this._fields[pos];
                        this[f]=new Function('n', 'if(arguments.length==1)this.a['+p+']=n;return this.a['+p+'];');
                    }
                }

            }
        });

        fieldmapper[cl] = window[cl]; // alias into place

        if (fieldmapper.IDL && fieldmapper.IDL.loaded) 
            fieldmapper[cl].Identifier = fieldmapper.IDL.fmclasses[cl].pkey;

        fieldmapper[cl].prototype.fromStoreItem = _fromStoreItem;
        fieldmapper[cl].toStoreData = _toStoreData;
        fieldmapper[cl].toStoreItem = _toStoreItem;
        fieldmapper[cl].prototype.toStoreItem = function ( args ) { return _toStoreItem(this, args); };
        fieldmapper[cl].initStoreData = _initStoreData;
        fieldmapper[cl].prototype.toHash = _toHash;
        fieldmapper[cl].toHash = _toHash;
        fieldmapper[cl].prototype.fromHash = _fromHash;
        fieldmapper[cl].fromHash = _fromHash;
    };

    fieldmapper._request = function ( meth, staff, params ) {
        var ses = OpenSRF.CachedClientSession( meth[0] );
        if (!ses) return null;

        var result = null;
        var args = {};

        if (dojo.isArray(params)) {
            args.params = params;
        } else {

            if (dojo.isObject(params)) {
                args = params;
            } else {
                args.params = [].splice.call(arguments, 2, arguments.length - 2);
            }

        }

        if (!args.async && !args.timeout) args.timeout = 10;

        if(!args.onmethoderror) {
            args.onmethoderror = function(r, stat, stat_text) {
                throw new Error('Method error: ' + r.stat + ' : ' + stat_text);
            };
            }

        if(!args.ontransporterror) {
            args.ontransporterror = function(xreq) {
                throw new Error('Transport error method='+args.method+', status=' + xreq.status);
            };
            }

        if (!args.onerror) {
            args.onerror = function (r) {
                throw new Error('Request error encountered! ' + r);
            };
            }

        if (!args.oncomplete) {
            args.oncomplete = function (r) {
                var x = r.recv();
                if (x) result = x.content();
            };
            }

        args.method = meth[1];
        if (staff && meth[2]) args.method += '.staff';

        ses.request(args).send();

        return result;
    };

    fieldmapper.standardRequest = function (meth, params) { return fieldmapper._request(meth, false, params); };
    fieldmapper.Fieldmapper.prototype.standardRequest = fieldmapper.standardRequest;

    fieldmapper.staffRequest = function (meth, params) { return fieldmapper._request(meth, true, params); };
    fieldmapper.Fieldmapper.prototype.staffRequest = fieldmapper.staffRequest;

    fieldmapper.OpenSRF = {};

    /*    Methods are defined as [ service, method, have_staff ]
        An optional 3rd component is when a method is followed by true, such methods
        have a staff counterpart and should have ".staff" appended to the method 
        before the method is called when in XUL mode */
    fieldmapper.OpenSRF.methods = {
        FETCH_ORG_BY_SHORTNAME : ['open-ils.actor','open-ils.actor.org_unit.retrieve_by_shortname'],
        FETCH_ORG_SETTING : ['open-ils.actor','open-ils.actor.ou_setting.ancestor_default'],
        FETCH_ORG_SETTING_BATCH : ['open-ils.actor','open-ils.actor.ou_setting.ancestor_default.batch']
    };
   
    
    //** FROM HASH **/
    function _fromHash (_hash) {
        for ( var i=0; i < this._fields.length; i++) {
            if (_hash[this._fields[i]] != null)
                this[this._fields[i]]( _hash[this._fields[i]] );
        }
        return this;
    }

    function _toHash (includeNulls, virtFields) {
        var _hash = {};
        var i;
        for (i=0; i < this._fields.length; i++) {
            if (includeNulls || this[this._fields[i]]() != null) {
                if (this[this._fields[i]]() == null)
                    _hash[this._fields[i]] = null;
                else
                    _hash[this._fields[i]] = '' + this[this._fields[i]]();
            }
        }

        if (virtFields && virtFields.length > 0) {
            for (i = 0; i < virtFields.length; i++) {
                if (!_hash[virtFields[i]])
                    _hash[virtFields[i]] = null;
            }
        }

        return _hash;
    }
    //** FROM HASH **/


    /** FROM dojoData **/
    function _fromStoreItem (data) {
        this.fromHash(data);

        var i;
        for (i = 0; this._ignore_fields && i < this._ignore_fields.length; i++)
            this[this._ignore_fields[i]](null);

        for (i = 0; this._fields && i < this._fields.length; i++) {
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

        var i, j;
        for (i = 0; list && i < list.length; i++) data.items.push( list[i].toHash(true, params.virtualFields) );

        if (params.children && params.parent) {
            var _hash_list = data.items;

            var _find_root = {};
            for (i = 0; _hash_list && i < _hash_list.length; i++) {
                _find_root[_hash_list[i][params.identifier]] = _hash_list[i]; 
            }

            var item_data = [];
            for (i = 0; _hash_list && i < _hash_list.length; i++) {
                var obj = _hash_list[i];
                obj[params.children] = [];

                for (j = 0; _hash_list && j < _hash_list.length; j++) {
                    var kid = _hash_list[j];
                    if (kid[params.parent] == obj[params.identifier]) {
                        obj[params.children].push( { _reference : kid[params.identifier] } );
                        kid._iskid = true;
                        if (_find_root[kid[params.identifier]]) delete _find_root[kid[params.identifier]];
                    }
                }

                item_data.push( obj );
            }

            for (j in _find_root) {
                _find_root[j]['_top'] = 'true';
                if (!_find_root[j][params.parent])
                    _find_root[j]['_trueRoot'] = 'true';
            }

            data.items = item_data;
        }

        return data;
    }
    /** FROM dojoData **/



    /** ! Begin code that executes on page load */

    if (!window.fmclasses) dojo.require("fieldmapper.fmall", true);
    for( var cl in fmclasses ) {
        fieldmapper.vivicateClass(cl);
    }

    // if we were NOT called by the IDL loader ...
    // XXX This is now deprecated in preference to fieldmapper.AutoIDL
    if ( !(fieldmapper.IDL && fieldmapper.IDL.loaded) ) {

        fieldmapper.cmsa.Identifier = 'alias';
        fieldmapper.cmc.Identifier = 'name';
        fieldmapper.i18n_l.Identifier = 'code';
        fieldmapper.ccpbt.Identifier = 'code';
        fieldmapper.ccnbt.Identifier = 'code';
        fieldmapper.cbrebt.Identifier = 'code';
        fieldmapper.cubt.Identifier = 'code';
        fieldmapper.ccm.Identifier = 'code';
        fieldmapper.cvrfm.Identifier = 'code';
        fieldmapper.clm.Identifier = 'code';
        fieldmapper.cam.Identifier = 'code';
        fieldmapper.cifm.Identifier = 'code';
        fieldmapper.citm.Identifier = 'code';
        fieldmapper.cblvl.Identifier = 'code';
        fieldmapper.clfm.Identifier = 'code';
        fieldmapper.mous.Identifier = 'usr';
        fieldmapper.mowbus.Identifier = 'usr';
        fieldmapper.moucs.Identifier = 'usr';
        fieldmapper.mucs.Identifier = 'usr';
        fieldmapper.mus.Identifier = 'usr';
        fieldmapper.rxbt.Identifier = 'xact';
        fieldmapper.rxpt.Identifier = 'xact';
        fieldmapper.cxt.Identifier = 'name';
        fieldmapper.amtr.Identifier = 'matchpoint';
        fieldmapper.coust.Identifier = 'name';

    }


    /** FROM dojoData **/
    /* set up some known class attributes */
    if (fieldmapper.aou) fieldmapper.aou.prototype._ignore_fields = ['children'];
    if (fieldmapper.aout) fieldmapper.aout.prototype._ignore_fields = ['children'];
    if (fieldmapper.pgt) fieldmapper.pgt.prototype._ignore_fields = ['children'];

    fieldmapper.aou.toStoreData = function (list, label) {
        if (!label) label = 'shortname';
        return _toStoreData.call(this, list, label, { 'parent' : 'parent_ou', 'children' : 'children' });
    };

    fieldmapper.aout.toStoreData = function (list, label) {
        if (!label) label = 'name';
        return _toStoreData.call(this, list, label, { 'parent' : 'parent', 'children' : 'children' });
    };

    fieldmapper.pgt.toStoreData = function (list, label) {
        if (!label) label = 'name';
        return _toStoreData.call(this, list, label, { 'parent' : 'parent', 'children' : 'children' });
    };
    /** FROM dojoData **/
    

}



