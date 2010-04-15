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

if(!dojo._hasResource["openils.BibTemplate"]) {

    dojo.require('dojox.data.dom');
    dojo._hasResource["openils.BibTemplate"] = true;
    dojo.provide("openils.BibTemplate");
    dojo.declare('openils.BibTemplate', null, {

        constructor : function(kwargs) {
            this.root = kwargs.root;
            this.record = kwargs.record;
            this.org_unit = kwargs.org_unit || '-';
            this.locale = kwargs.locale || 'en-US';

            this.mode = 'biblio-record_entry';
            this.default_datatype = 'marcxml-uris';
            if (kwargs.metarecord) {
                this.record = kwargs.metarecord;
                this.mode = 'metabib-metarecord';
                this.default_datatype = 'mods';
            }
        },

        render : function() {
            var all_slots = dojo.query('*[type^=opac/slot-data]', this.root);
            var default_datatype = this.default_datatype;
        
            var slots = {};
            dojo.forEach(all_slots, function(s){
                // marcxml-uris does not include copies, which avoids timeouts
                // with bib records that have hundreds or thousands of copies
                var current_datatype = default_datatype;
        
                if (s.getAttribute('type').indexOf('+') > -1) 
                    current_datatype = s.getAttribute('type').split('+').reverse()[0];
        
                if (!slots[current_datatype]) slots[current_datatype] = [];
                slots[current_datatype].push(s);
            });
        
            for (var datatype in slots) {

                (function (slot_list,dtype,mode,rec,org) {

                    dojo.xhrGet({
                        url: '/opac/extras/unapi?id=tag:opac:' + mode + '/' + rec + '/' + org + '&format=' + dtype + '&locale=' + this.locale,
                        handleAs: 'xml',
                        load: function (bib) {

                            dojo.forEach(slot_list, function (slot) {
                                var joiner = slot.getAttribute('join') || ' ';

                                var slot_handler = dojo.map(
                                    dojo.query( '*[type=opac/slot-format]', slot ).orphan(), // IE, I really REALLY hate you
                                    function(x){ return dojox.data.dom.textContent(x) || x.innerHTML }
                                ).join('');

                                if (slot_handler) slot_handler = new Function('item', slot_handler);
                                else slot_handler = new Function('item','return dojox.data.dom.textContent(item);');
                
                                var item_list = dojo.query(
                                    slot.getAttribute('query'),
                                    bib
                                );

                                if (item_list.length) slot.innerHTML = dojo.map(item_list, slot_handler).join(joiner);

                                delete(slot_handler);

                            });
                       }
                    });

                })(slots[datatype],datatype,this.mode,this.record,this.org_unit);
            
            }

            return true;
        }
    });

}
