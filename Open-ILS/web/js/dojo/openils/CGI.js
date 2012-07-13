/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * Bill Erickson <erickson@esilibrary.com>
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

if(!dojo._hasResource["openils.CGI"]) {

    dojo._hasResource["openils.CGI"] = true;
    dojo.provide("openils.CGI");
    dojo.declare('openils.CGI', null, {

        constructor : function(args) {

            this._keys = new Array();
            this.data = new Object();

            var query = location.search.replace(/^\?/,"");
            this.server_name = location.href.replace(/^https?:\/\/([^\/]+).+$/,"$1");
            this.base_url = location.href.replace(/(.*)\?.*/, '$1'); // proto://hostname/full/path

            // if the user specifies URL components, override URL
            // components pulled from the current page
            if (args) {
                if (url = args.url) { // assignment
                    this.base_url = url.replace(/(.*)\?.*/, '$1');
                    query = '';
                    if (url.match(/\?(.*)/))
                        query = url.match(/\?(.*)/)[0];
                }
                if (args.query)
                    query = args.query;

                query = query.replace(/^\?/, '');
            }

            var key = ""; 
            var value = "";
            var inkey = true;
            var invalue = false;

            for( var idx = 0; idx!= query.length; idx++ ) {

                var c = query.charAt(idx);

                if( c == "=" )	{
                    invalue = true;
                    inkey = false;
                    continue;
                } 

                if(c == "&" || c == ";") {
                    inkey = 1;
                    invalue = 0;
                    if( ! this.data[key] ) this.data[key] = [];
                    this.data[key].push(decodeURIComponent(value));
                    this._keys.push(key);
                    key = ""; value = "";
                    continue;
                }

                if(inkey) key += c;
                else if(invalue) value += c;
            }

            if (key.length) {
                if( ! this.data[key] ) this.data[key] = [];
                this.data[key].push(decodeURIComponent(value));
                this._keys.push(key);
            }
        },

        /* returns the value for the given param.  If there is only one value for the
           given param, it returns that value.  Otherwise it returns an array of values
         */
        param : function(p, val, push) {
            if (p == null || p == '') // invalid param name
                return null;

            // set param value
            if (arguments.length > 1) { 
                if (this.keys().indexOf(p) == -1)
                    this._keys.push(p);

                if (dojo.isArray(this.data[p])) {
                    if (push) {
                        this.data[p].push(val);
                    } else {
                        this.data[p] = val;
                    }
                } else {
                    this.data[p] = val;
                }
            }

            if(this.data[p] == null)
                return null;
            if(this.data[p].length == 1)
                return this.data[p][0];
            return this.data[p];
        },

        /* returns an array of param names */
        keys : function() {
            return this._keys;
        },

        /* returns the URI-encoded query string */
        queryString : function() {
            var query = "";
            var _this = this;

            dojo.forEach(this.keys(),
                function(key) {
                    var params = _this.param(key);
                    if (!dojo.isArray(params))
                        params = [params];

                    dojo.forEach(params,
                        function(param) {
                            if (param == null) return;
                            query += ';' + key + '=' + encodeURIComponent(param);
                        }
                    );
                }
            );

            return query.replace(/^;/, '?');
        },

        url : function() {
            return this.base_url + this.queryString();
        },

        /* debugging method */
        toString : function() {
            var query = "";
            var keys = this.keys();

            for( var k in keys ) {
                query += keys[k] + " : ";
                var params = this.param(keys[k]);

                for( var p in params ) {
                    query +=  params[p] + " ";
                }
                query += "\n";
            }
            return query;
        }
    });
}


