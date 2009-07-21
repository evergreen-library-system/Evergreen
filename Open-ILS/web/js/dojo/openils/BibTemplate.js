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
        },

        render : function() {
            var all_slots = dojo.query('*[type^=opac/slot-data]', this.root);
        
            var slots = {};
            dojo.forEach(all_slots, function(s){
                var datatype = 'marcxml-full';
        
                if (s.getAttribute('type').indexOf('+') > -1) 
                    datatype = s.getAttribute('type').split('+').reverse()[0];
        
                if (!slots[datatype]) slots[datatype] = [];
                slots[datatype].push(s);
            });
        
            for (var datatype in slots) {

                (function (slot_list,dtype,rec,org) {

                    dojo.xhrGet({
                        url: '/opac/extras/unapi?id=tag:opac:biblio-record_entry/' + rec + '/' + org + '&format=' + datatype,
                        handleAs: 'xml',
                        load: function (bib) {

                            dojo.forEach(slot_list, function (slot) {
                                var joiner = slot.getAttribute('join') || ' ';

                                var slot_handler = dojo.map(
                                    dojo.query('script[type=opac/slot-format]', slot).orphan(),
                                    function(x){
                                        if(dojo.isIE) return x.innerHTML;
                                        return dojox.data.dom.textContent(x)
                                    }
                                );

                                slot_handler = slot_handler.join('');

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

                })(slots[datatype],datatype,this.record,this.org_unit);
            
            }

            return true;
        }
    });

}
