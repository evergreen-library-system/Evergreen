/* ---------------------------------------------------------------------------
 * Copyright (C) 2009  Equinox Software, Inc.
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

if(!dojo._hasResource["MARC.Batch"]) {

    dojo.require('dojox.xml.parser');
    dojo.require('MARC.Record');

    dojo._hasResource["MARC.Batch"] = true;
    dojo.provide("MARC.Batch");
    dojo.declare('MARC.Batch', null, {

        constructor : function(kwargs) {
            this.ready = false;
            this.records = [];
            this.source = kwargs.source;
            this.delimiter = kwargs.delimiter
            this.current_record = 0;

            if (this.source) this.ready = true;
            if (!this.ready && kwargs.url) this.fetchURL( kwargs.url );

            if (this.ready) this.parse();
        },

        parse : function () {
            if (dojo.isObject( this.source )) { // assume an xml collection document
                this.source = dojo.query('record', this.source);
                this.type = 'xml';
            } else if (this.source.match(/^\s*</)) { // this is xml text
                this.source = dojox.xml.parser.parse( this.source );
                this.parse();
            } else { // must be a marcbreaker doc. split on blank lines
                this.source = this.source.split(/^$/);
                this.type = 'marcbreaker';
            }
        },

        fetchURL : function (u) {
            var me = this;
            dojo.xhrGet({
                url     : u,
                sync    : true,
                handleAs: 'text',
                load    : function (mrc) {
                    me.source = mrc;
                    me.ready = true;
                }
            });
        },

        next : function () {
            var chunk = this.source[this.current_record++];

            if (chunk) {
                var args = {};
                args[this.type] = chunk;
                if (this.delimiter) args.delimiter = this.delimiter;
                return new MARC.Record(args);
            }

            return null;
        }

    });
}
            
            

