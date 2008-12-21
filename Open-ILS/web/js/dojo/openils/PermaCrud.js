/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Equinox Software, Inc
 * Mike Rylander <miker@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ---------------------------------------------------------------------------
 */

if(!dojo._hasResource["openils.PermaCrud"]) {

    dojo._hasResource["openils.PermaCrud"] = true;
    dojo.provide("openils.PermaCrud");
    dojo.require("openils.User");

    dojo.declare('openils.PermaCrud', null, {

        session : null,
        authtoken : null,
        connnected : false,

        constructor : function ( kwargs ) {
            kwargs = kwargs || {};

            this.authtoken = kwargs.authtoken;

            this.session =
                kwargs.session ||
                new OpenSRF.ClientSession('open-ils.pcrud');

            if (
                this.session &&
                this.session.state == OSRF_APP_SESSION_CONNECTED
            ) this.connected = true;
        },

        auth : function (token) {
            if (token) this.authtoken = token;
            return this.authtoken || openils.User.authtoken;
        },

        connect : function ( onerror ) {
            if (!this.connected && !this.session.connect()) {
                this.connected = false;
                if (onerror) onerror(this.session);
                return false;
            }
            this.connected = true;
            return true;
        },

        disconnect : function ( onerror ) {
            if (!this.session.disconnect()) {
                if (onerror) onerror(this.session);
                return false;
            }
            return true;
        },
        

	    retrieve : function ( fm_class /* Fieldmapper class hint */, id /* Fieldmapper object primary key value */,  opts /* Option hash */) {
            var req_hash = dojo.mixin(
                opts, 
                { method : 'open-ils.pcrud.retrieve.' + fm_class,
                  params : [ this.auth(), id ]
                }
            );

            var _pcrud = this;
            var req = this.session.request( req_hash );

            if (!req.onerror)
                req.onerror = function (r) { throw js2JSON(r); };

            if (!req.oncomplete)
                req.oncomplete = function (r) { r.result = r.recv(); _pcrud.last_result = r.result; };

            req.send();

            return req;
	    },

	    retrieveAll : function ( fm_class /* Fieldmapper class hint */, opts /* Option hash */) {
            var pkey = fieldmapper[fm_class].Indentifier;

            var order_by = {};
            if (opts.order_by) order_by.order_by = opts.order_by;
            if (opts.select) order_by.select = opts.select;

            var req_hash = dojo.mixin(
                opts, 
                { method : 'open-ils.pcrud.search.' + fm_class + '.atomic',
                  params : [ this.auth(), { fieldmapper[fm_class].Indentifier : { '!=' : null } }, order_by ]
                }
            );

            var _pcrud = this;
            var req = this.session.request( req_hash );

            if (!req.onerror)
                req.onerror = function (r) { throw js2JSON(r); };

            if (!req.oncomplete)
                req.oncomplete = function (r) { r.result = r.recv(); _pcrud.last_result = r.result; };

            req.send();

            return req;
	    },

	    search : function ( fm_class /* Fieldmapper class hint */, search /* Fieldmapper query object */, opts /* Option hash */) {
            var pkey = fieldmapper[fm_class].Indentifier;

            var order_by = {};
            if (opts.order_by) order_by.order_by = opts.order_by;
            if (opts.select) order_by.select = opts.select;

            var req_hash = dojo.mixin(
                opts, 
                { method : 'open-ils.pcrud.search.' + fm_class + '.atomic',
                  params : [ this.auth(), search, order_by ]
                }
            );

            var _pcrud = this;
            var req = this.session.request( req_hash );

            if (!req.onerror)
                req.onerror = function (r) { throw js2JSON(r); };

            if (!req.oncomplete)
                req.oncomplete = function (r) { r.result = r.recv(); _pcrud.last_result = r.result; };

            req.send();

            return req;
	    },

        _CUD : function ( method /* 'create' or 'update' or 'delete' */ list /* Fieldmapper object */, opts /* Option hash */) {

            if (dojo.isArray(list)) {
                if (list.classname) list = [ list ];
            } else {
                list = [ list ];
            }

            if (!this.connected) this.connect();

            var _pcrud = this;
            var final_complete = opts.oncomplete;
            var final_error = opts.onerror;

            function _CUD_recursive ( obj_list, pos, final_complete ) {
                var obj = obj_list[pos];
                var req_hash = {
                    method : 'open-ils.pcrud.' + method + '.' + obj.classname,
                    params : [ _pcrud.auth(), obj ],
                    onerror : final_error || function (r) { _pcrud.disconnect(); throw '_CUD: Error creating, deleting or updating ' + js2JSON(obj); };
                };

                var req = _pcrud.session.request( req_hash );

                if (++pos == all_objs.length) {
                    req.oncomplete = function (r) {
                        _pcrud.commit();
                        _pcrud.disconnect();
                        final_complete(r);
                    };

                    req.onerror = function (r) {
                        _pcrud.disconnect();
                        final_error(r);
                    };

                } else {
                    req._pos = pos;
                    req._obj_list = obj_list;
                    req._final_complete = final_complete;
                    req.oncomplete = function (r) {
                        var res = r.recv();
                        if ( res && res.content() ) {
                            _CUD_recursive( r._obj_list, r._pos, r._final_complete );
                        } else {
                            _pcrud.disconnect();
                            throw '_CUD: Error creating, deleting or updating ' + js2JSON(obj);
                        }
                    };
                }

                req.send();
            }

            this.session.request({
                method : 'open-ils.pcrud.transaction.commit',
                timeout : 10,
                params : [ ses, modified_ou ],
                onerror : function (r) {
                    _pcrud.disconnect();
                    throw 'Transaction begin error';
                },      
                oncomplete : function (r) {
                    var res = r.recv();
                    if ( res && res.content() ) {
                        _CUD_recursive( list, 0 );
                    } else {
                        _pcrud.disconnect();
                        throw 'Transaction begin error';
                    }
                },
	        }).send();
        },

        create : function ( list, opts ) {
            this._CUD( 'create', list, opts );
        },

        update : function ( list, opts ) {
            this._CUD( 'update', list, opts );
        },

        delete : function ( list, opts ) {
            this._CUD( 'delete', list, opts );
        },

        apply : function ( list, opts ) {
            this._auto_CUD( list, opts );
        },

        _auto_CUD : function ( list /* Fieldmapper object */, opts /* Option hash */) {

            if (dojo.isArray(list)) {
                if (list.classname) list = [ list ];
            } else {
                list = [ list ];
            }

            if (!this.connected) this.connect();

            var _pcrud = this;
            var final_complete = opts.oncomplete;
            var final_error = opts.onerror;

            function _auto_CUD_recursive ( obj_list, pos, final_complete ) {
                var obj = obj_list[pos];

                var method;
                if (obj.isnew)     method = 'create';
                if (obj.ischanged) method = 'update';
                if (obj.isdeleted) method = 'delete';
                if (!method) throw 'No action detected';

                var req_hash = {
                    method : 'open-ils.pcrud.' + method + '.' + obj.classname,
                    params : [ _pcrud.auth(), obj ],
                    onerror : final_error || function (r) { _pcrud.disconnect(); throw '_auto_CUD: Error creating, deleting or updating ' + js2JSON(obj); };
                };

                var req = _pcrud.session.request( req_hash );

                if (++pos == all_objs.length) {
                    req.oncomplete = function (r) {
                        _pcrud.commit();
                        _pcrud.disconnect();
                        final_complete(r);
                    };

                    req.onerror = function (r) {
                        _pcrud.disconnect();
                        final_error(r);
                    };

                } else {
                    req._pos = pos;
                    req._obj_list = obj_list;
                    req._final_complete = final_complete;
                    req.oncomplete = function (r) {
                        var res = r.recv();
                        if ( res && res.content() ) {
                            _auto_CUD_recursive( r._obj_list, r._pos, r._final_complete );
                        } else {
                            _pcrud.disconnect();
                            throw '_auto_CUD: Error creating, deleting or updating ' + js2JSON(obj);
                        }
                    };
                }

                req.send();
            }

            this.session.request({
                method : 'open-ils.pcrud.transaction.commit',
                timeout : 10,
                params : [ ses, modified_ou ],
                onerror : function (r) {
                    _pcrud.disconnect();
                    throw 'Transaction begin error';
                },      
                oncomplete : function (r) {
                    var res = r.recv();
                    if ( res && res.content() ) {
                        _auto_CUD_recursive( list, 0 );
                    } else {
                        _pcrud.disconnect();
                        throw 'Transaction begin error';
                    }
                },
	        }).send();
        }

    });
}


