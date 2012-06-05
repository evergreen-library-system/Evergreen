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
    dojo.require("fieldmapper.Fieldmapper");
    dojo.require("openils.User");

    dojo.declare('openils.PermaCrud', null, {

        session : null,
        authtoken : null,
        connnected : false,
        authoritative : false,

        constructor : function ( kwargs ) {
            kwargs = kwargs || {};

            this.authtoken = kwargs.authtoken;
            this.authoritative = kwargs.authoritative;

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
            this.connected = false;
            return true;
            // disconnect returns nothing, which is null, which is not true, cause the following to always run ... arg.
            if (!this.session.disconnect()) {
                if (onerror) onerror(this.session);
                return false;
            }
        },

        _session_request : function ( args /* hash */, commitOnComplete /* set to true, else no */ ) {

            var me = this;
            var endstyle = 'rollback';
            var aopts = dojo.mixin({}, args);
            args = aopts;
            if (commitOnComplete) endstyle = 'commit';

            if (me.authoritative) {
                if (!me.connected) me.connect();
                if (args.timeout && !args.oncomplete && !args.onresponse) { // pure sync call
                    args.oncomplete = function (r) {
                        me.session.request('open-ils.pcrud.transaction.' + endstyle, me.auth());
                        me.session.disconnect();
                        me.disconnect();
                    };
                } else if (args.oncomplete) { // there's an oncomplete, fire that, and then end the transaction
                    var orig_oncomplete = args.oncomplete;
                    args.oncomplete = function (r) {
                        var ret;
                        try {
                            ret = orig_oncomplete(r);
                        } finally {
                            me.session.request('open-ils.pcrud.transaction.' + endstyle, me.auth());
                            me.session.disconnect();
                            me.disconnect();
                        }
                        return ret;
                    };
                }
                me.session.request('open-ils.pcrud.transaction.begin', me.auth());
            }
            return me.session.request( args );
        },

        retrieve : function ( fm_class /* Fieldmapper class hint */, id /* Fieldmapper object primary key value */,  opts /* Option hash */) {
            if(!opts) opts = {};
            var ffj = {};
            if (opts.join) ffj.join = opts.join;
            if (opts.flesh) ffj.flesh = opts.flesh;
            if (opts.flesh_fields) ffj.flesh_fields = opts.flesh_fields;
            var req_hash = dojo.mixin(
                opts, 
                { method : 'open-ils.pcrud.retrieve.' + fm_class,
                  params : [ this.auth(), id, ffj ]
                }
            );

            if (!opts.async && !opts.timeout) req_hash.timeout = 10;

            var _pcrud = this;
            var req = this._session_request( req_hash );

            if (!req.onerror)
                req.onerror = function (r) { throw js2JSON(r); };

            // if it's an async call and the user does not care about 
            // the responses, pull them off the network and discard them
            if (!req_hash.timeout && !req.oncomplete)
                req.oncomplete = function (r) { while(r.recv()){}; };

            req.send();

            // for synchronous calls with no handlers, return the first received value
            if (req_hash.timeout && !opts.oncomplete && !opts.onresponse) {
                var resp = req.recv();
                if(resp) return resp.content();
                return null;
            }

            return req;
        },

        retrieveAll : function ( fm_class /* Fieldmapper class hint */, opts /* Option hash */) {
            var pkey = fieldmapper[fm_class].Identifier;

            if(!opts) opts = {};
            var order_by = {};
            if (opts.order_by) order_by.order_by = opts.order_by;
            if (opts.select) order_by.select = opts.select;
            if (opts.limit) order_by.limit = opts.limit;
            if (opts.offset) order_by.offset = opts.offset;
            if (opts.join) order_by.join = opts.join;
            if (opts.flesh) order_by.flesh = opts.flesh;
            if (opts.flesh_fields) order_by.flesh_fields = opts.flesh_fields;
            
            var method = 'open-ils.pcrud.search.' + fm_class;
            if(!opts.streaming) method += '.atomic';

            var search = {};
            search[pkey] = { '!=' : null };

            var req_hash = dojo.mixin(
                opts, 
                { method : method,
                  params : [ this.auth(), search, order_by ]
                }
            );

            if (!opts.async && !opts.timeout) req_hash.timeout = 10;

            var _pcrud = this;
            var req = this._session_request( req_hash );

            if (!req.onerror)
                req.onerror = function (r) { throw js2JSON(r); };
            
            // if it's an async call and the user does not care about 
            // the responses, pull them off the network and discard them
            if (!req_hash.timeout && !req.oncomplete)
                req.oncomplete = function (r) { while(r.recv()){}; };

            req.send();

            // for synchronous calls with no handlers, return the first received value
            if (req_hash.timeout && !opts.oncomplete && !opts.onresponse) {
                var resp = req.recv();
                if(resp) return resp.content();
                return null;
            }

            return req;
        },

        search : function ( fm_class /* Fieldmapper class hint */, search /* Fieldmapper query object */, opts /* Option hash */) {
            var return_type = 'search';
            if(!opts) opts = {};
            var order_by = {};
            if (opts.order_by) order_by.order_by = opts.order_by;
            if (opts.select) order_by.select = opts.select;
            if (opts.limit) order_by.limit = opts.limit;
            if (opts.offset) order_by.offset = opts.offset;
            if (opts.join) order_by.join = opts.join;
            if (opts.flesh) order_by.flesh = opts.flesh;
            if (opts.flesh_fields) order_by.flesh_fields = opts.flesh_fields;
            if (opts.id_list) return_type = 'id_list';

            var method = 'open-ils.pcrud.' + return_type + '.' + fm_class;
            if(!opts.streaming) method += '.atomic';

            var req_hash = dojo.mixin(
                opts, 
                { method : method,
                  params : [ this.auth(), search, order_by ]
                }
            );

            if (!opts.async && !opts.timeout) req_hash.timeout = 10;

            var _pcrud = this;
            var req = this._session_request( req_hash );

            if (!req.onerror)
                req.onerror = function (r) { throw js2JSON(r); };

            // if it's an async call and the user does not care about 
            // the responses, pull them off the network and discard them
            if (!req_hash.timeout && !req.oncomplete)
                req.oncomplete = function (r) { while(r.recv()){}; };

            req.send();

            // for synchronous calls with no handlers, return the first received value
            if (req_hash.timeout && !opts.oncomplete && !opts.onresponse) {
                var resp = req.recv();
                if(resp) return resp.content();
                return null;
            }

            return req;
        },

        _CUD : function ( method /* 'create' or 'update' or 'delete' */, list /* Fieldmapper object */, opts /* Option hash */) {
            if(!opts) opts = {};

            if (dojo.isArray(list)) {
                if (list.classname) list = [ list ];
            } else {
                list = [ list ];
            }

            if (!this.connected) this.connect();

            var _pcrud = this;
            var _return_list = [];

            function _CUD_recursive ( obj_list, pos, final_complete, final_error ) {
                var obj = obj_list[pos];
                var req_hash = {
                    method : 'open-ils.pcrud.' + method + '.' + obj.classname,
                    params : [ _pcrud.auth(), obj ],
                    onerror : final_error || function (r) { _pcrud.disconnect(); throw '_CUD: Error creating, deleting or updating ' + js2JSON(obj); }
                };

                var req = _pcrud.session.request( req_hash );
                req._final_complete = final_complete;
                req._final_error = final_error;

                if (++pos == obj_list.length) {
                    req.oncomplete = function (r) {
                        var res = r.recv();

                        if ( res && res.content() ) {
                            _return_list.push( res.content() );
                            _pcrud.session.request({
                                method : 'open-ils.pcrud.transaction.commit',
                                timeout : 10,
                                params : [ _pcrud.auth() ],
                                onerror : function (r) {
                                    _pcrud.disconnect();
                                    if (req._final_error) req._final_error(r)
                                    else throw 'Transaction commit error';
                                },      
                                oncomplete : function (r) {
                                    var res = r.recv();
                                    if ( res && res.content() ) {
                                        if(req._final_complete)
                                            req._final_complete(req, _return_list);
                                        _pcrud.disconnect();
                                    } else {
                                        _pcrud.disconnect();
                                        if (req._final_error) req._final_error(r)
                                        else throw 'Transaction commit error';
                                    }
                                },
                            }).send();
                        } else {
                            _pcrud.disconnect();
                            if (req._final_error) req._final_error(r)
                            else throw '_CUD: Error creating, deleting or updating ' + js2JSON(obj);
                        }
                    };

                    req.onerror = function (r) {
                        _pcrud.disconnect();
                        if (req._final_error) req._final_error(r);
                        else throw '_CUD: Error creating, deleting or updating ' + js2JSON(obj);
                    };

                } else {
                    req._pos = pos;
                    req._obj_list = obj_list;
                    req.oncomplete = function (r) {
                        var res = r.recv();
                        if ( res && res.content() ) {
                            _return_list.push( res.content() );
                            _CUD_recursive( r._obj_list, r._pos, req._final_complete, req._final_error );
                        } else {
                            _pcrud.disconnect();
                            if (req._final_error) req._final_error(r);
                            else throw '_CUD: Error creating, deleting or updating ' + js2JSON(obj);
                        }
                    };
                    req.onerror = function (r) {
                        _pcrud.disconnect();
                        if (req._final_error) req._final_error(r);
                        throw '_CUD: Error creating, deleting or updating ' + js2JSON(obj);
                    };
                }

                req.send();
            }

            var f_complete = opts.oncomplete;
            var f_error = opts.onerror;

            this.session.request({
                method : 'open-ils.pcrud.transaction.begin',
                timeout : 10,
                params : [ _pcrud.auth() ],
                onerror : function (r) {
                    _pcrud.disconnect();
                    throw 'Transaction begin error';
                },      
                oncomplete : function (r) {
                    var res = r.recv();
                    if ( res && res.content() ) {
                        _CUD_recursive( list, 0, f_complete, f_error );
                    } else {
                        _pcrud.disconnect();
                        throw 'Transaction begin error';
                    }
                },
            }).send();

            return _return_list;

        },

        create : function ( list, opts ) {
            return this._CUD( 'create', list, opts );
        },

        update : function ( list, opts ) {
            var id_list = this._CUD( 'update', list, opts );
            var obj_list = [];

            for (var idx = 0; idx < id_list.length; idx++) {
                obj_list.push(
                    this.retrieve( list[idx].classname, id_list[idx] )
                );
            }

            return obj_list;
        },

	/* 
	 * 'delete' is a reserved keyword in JavaScript and can't be used
	 * in browsers like IE or Chrome, so we define a safe synonym
     * NOTE: delete() is now removed -- use eliminate instead

        delete : function ( list, opts ) {
            return this._CUD( 'delete', list, opts );
        },

	 */
        eliminate: function ( list, opts ) {
            return this._CUD( 'delete', list, opts );
        },

        apply : function ( list, opts ) {
            this._auto_CUD( list, opts );
        },

        _auto_CUD : function ( list /* Fieldmapper object */, opts /* Option hash */) {

            if(!opts) opts = {};

            if (dojo.isArray(list)) {
                if (list.classname) list = [ list ];
            } else {
                list = [ list ];
            }

            if (!this.connected) this.connect();

            var _pcrud = this;
            var _return_list = [];

            function _auto_CUD_recursive ( obj_list, pos, final_complete, final_error ) {
                var obj = obj_list[pos];

                var method;
                if (obj.ischanged()) method = 'update';
                if (obj.isnew())     method = 'create';
                if (obj.isdeleted()) method = 'delete';
                if (!method) {
                    return _auto_CUD_recursive(obj_list, pos+1, final_complete, final_error);
                }

                var req_hash = {
                    method : 'open-ils.pcrud.' + method + '.' + obj.classname,
                    timeout : 10,
                    params : [ _pcrud.auth(), obj ],
                    onerror : final_error || function (r) { _pcrud.disconnect(); throw '_auto_CUD: Error creating, deleting or updating ' + js2JSON(obj); }
                };

                var req = _pcrud.session.request( req_hash );
                req._final_complete = final_complete;
                req._final_error = final_error;

                if (++pos == obj_list.length) {
                    req.oncomplete = function (r) {
                        var res = r.recv();

                        if ( res && res.content() ) {
                            _return_list.push( res.content() );
                            _pcrud.session.request({
                                method : 'open-ils.pcrud.transaction.commit',
                                timeout : 10,
                                params : [ _pcrud.auth() ],
                                onerror : function (r) {
                                    _pcrud.disconnect();
                                    throw 'Transaction commit error';
                                },      
                                oncomplete : function (r) {
                                    var res = r.recv();
                                    if ( res && res.content() ) {
                                        if (req._final_complete) 
                                            req._final_complete(req, _return_list);
                                        _pcrud.disconnect();
                                    } else {
                                        _pcrud.disconnect();
                                        if (req._final_error) req._final_error(r);
                                        else throw 'Transaction commit error';
                                    }
                                },
                            }).send();
                        } else {
                            _pcrud.disconnect();
                            if (req._final_error) req._final_error(r)
                            else throw '_auto_CUD: Error creating, deleting or updating ' + js2JSON(obj);
                        }
                    };

                    req.onerror = function (r) {
                        _pcrud.disconnect();
                        if (req._final_error) req._final_error(r);
                    };

                } else {
                    req._pos = pos;
                    req._obj_list = obj_list;
                    req.oncomplete = function (r) {
                        var res = r.recv();
                        if ( res && res.content() ) {
                            _return_list.push( res.content() );
                            _auto_CUD_recursive( r._obj_list, r._pos, req._final_complete, req._final_error );
                        } else {
                            _pcrud.disconnect();
                            if (req._final_error) req._final_error(r);
                            else throw '_auto_CUD: Error creating, deleting or updating ' + js2JSON(obj);
                        }
                    };
                }

                req.send();
            }

            var f_complete = opts.oncomplete;
            var f_error = opts.onerror;

            this.session.request({
                method : 'open-ils.pcrud.transaction.begin',
                timeout : 10,
                params : [ _pcrud.auth() ],
                onerror : function (r) {
                    _pcrud.disconnect();
                    throw 'Transaction begin error';
                },      
                oncomplete : function (r) {
                    var res = r.recv();
                    if ( res && res.content() ) {
                        _auto_CUD_recursive( list, 0, f_complete, f_error );
                    } else {
                        _pcrud.disconnect();
                        throw 'Transaction begin error';
                    }
                },
            }).send();

            return _return_list;
        }

    });
}


