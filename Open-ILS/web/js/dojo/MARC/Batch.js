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
            this.current_record = 0;
            this.records = [];
            this.type = kwargs.type || 'xml';
            this.source = kwargs.source;

            if (kwargs.url) this.fetchURL( kwargs.url );
            this.parse();
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

        next : function () { return this.records[this.current_record++] },

        parse : function () {
            if (this.source && dojo.isObject( this.source )) { // assume an xml collection document
                this.records = dojo.map(
                    dojo.query('record', this.source),
                    function (r) { return new MARC.Record({xml:r}) }
                );
            } else if (this.source && this.source.match(/^\s*</)) { // this is xml text
                this.source = dojox.xml.parser.parse( this.source );
                this.parse();
            } else if (this.source) { // must be a breaker doc. split on blank lines
                this.records = dojo.map(
                    this.source.split(/^$/),
                    function (r) { return new MARC.Record({breaker:r}) }
                );
            }
        }
    });
}
            
            

