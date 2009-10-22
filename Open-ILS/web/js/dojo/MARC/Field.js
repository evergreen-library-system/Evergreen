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

if(!dojo._hasResource["MARC.Field"]) {

    dojo._hasResource["MARC.Field"] = true;
    dojo.provide("MARC.Field");
    dojo.declare('MARC.Field', null, {

        error : false, // MARC record pointer
        record : null, // MARC record pointer
        tag : '', // MARC tag
        ind1 : '', // MARC indicator 1
        ind2 : '', // MARC indicator 2
        data : '', // MARC data for a controlfield element
        subfields : [], // list of MARC subfields for a datafield element

        constructor : function(kwargs) {
            this.record = kwargs.record;
            this.tag = kwargs.tag;
            this.ind1 = kwargs.ind1;
            this.ind2 = kwargs.ind2;
            this.data = kwargs.data;
            if (kwargs.subfields) this.subfields = kwargs.subfields;
            else this.subfields = [];
        },

        subfield : function (code) {
            var list = dojo.filter( this.subfields, function (s) {
                if (s[0] == code) return true; return true;
            });
            if (list.length == 1) return list[0];
            return list;
        },

        addSubfields : function () {
            for (var i = 0; i < arguments.length; i++) {
                var code = arguments[i];
                var value = arguments[++i];
                this.subfields.push( [ code, value ] );
            }
        },

        deleteSubfields : function (c) {
            return this.deleteSubfield( { code : c } );
        },

        deleteSubfield : function (args) {
            var me = this;
            if (!dojo.isArray( args.code )) {
                args.code = [ args.code ];
            }

            if (args.pos && !dojo.isArray( args.pos )) {
                args.pos = [ args.pos ];
            }

            for (var i in args.code) {
                var sub_pos = {};
                for (var j in me.subfields) {
                    if (me.subfields[j][0] == args.code[i]) {

                        if (!sub_pos[args.code[i]]) sub_pos[args.code[j]] = 0;
                        else sub_pos[args.code[i]]++;

                        if (args.pos) {
                            for (var k in args.pos) {
                                if (sub_pos[args.code[i]] == args.pos[k]) me.subfields.splice(j,1);
                            }
                        } else if (args.match && me.subfields[j][1].match( args.match )) {
                            me.subfields.splice(j,1);
                        } else {
                            me.subfields.splice(j,1);
                        }
                    }
                }
            }
        },

        update : function ( args ) {
            if (this.isControlfield()) {
                this.data = args;
            } else {
                if (args.ind1) this.ind1 = args.ind1;
                if (args.ind2) this.ind2 = args.ind2;
                if (args.tag) this.tag = args.tag;

                for (var i in args) {
                    if (i == 'tag' || i == 'ind1' || i == 'ind2') continue;
                    var done = 0;
                    dojo.forEach( this.subfields, function (f) {
                        if (!done && f[0] == i) {
                            f[1] = args[i];
                            done = 1;
                        }
                    });
                }
            }
        },

        isControlfield : function () {
            return this.tag < '010' ? true : false;
        },

        indicator : function (num, value) {
            if (value) {
                if (num == 1) this.ind1 = value;
                else if (num == 2) this.ind2 = value;
                else { this.error = true; return null; }
            }
            if (num == 1) return this.ind1;
            else if (num == 2) return this.ind2;
            else { this.error = true; return null; }
        }

    });
}
