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

        constructor : function() {

            this._keys = new Array();
            this.data = new Object();

            var string = location.search.replace(/^\?/,"");
            this.server_name = location.href.replace(/^https?:\/\/([^\/]+).+$/,"$1");

            var key = ""; 
            var value = "";
            var inkey = true;
            var invalue = false;

            for( var idx = 0; idx!= string.length; idx++ ) {

                var c = string.charAt(idx);

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

            if( ! this.data[key] ) this.data[key] = [];
            this.data[key].push(decodeURIComponent(value));
            this._keys.push(key);
        },

        /* returns the value for the given param.  If there is only one value for the
           given param, it returns that value.  Otherwise it returns an array of values
         */
        param : function(p) {
            if(this.data[p] == null) return null;
            if(this.data[p].length == 1)
                return this.data[p][0];
            return this.data[p];
        },

        /* returns an array of param names */
        keys : function() {
            return this._keys;
        },

        /* debugging method */
        toString : function() {
            var string = "";
            var keys = this.keys();

            for( var k in keys ) {
                string += keys[k] + " : ";
                var params = this.param(keys[k]);

                for( var p in params ) {
                    string +=  params[p] + " ";
                }
                string += "\n";
            }
            return string;
        }
    });
}


