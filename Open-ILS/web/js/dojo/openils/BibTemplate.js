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

    dojo.require('DojoSRF');
    dojo.require('dojox.xml.parser');
    dojo.require('dojo.string');
    dojo._hasResource["openils.BibTemplate"] = true;
    dojo.provide("openils.BibTemplate");
    dojo.declare('openils.BibTemplate', null, {

        constructor : function(kwargs) {
            this.root = kwargs.root;
            this.subObjectLimit = kwargs.subObjectLimit;
            this.subObjectOffset = kwargs.subObjectOffset;
            this.tagURI = kwargs.tagURI;
            this.xml = kwargs.xml;
            this.record = kwargs.record;
            this.org_unit = kwargs.org_unit || '-';
            this.depth = kwargs.depth;
            this.sync = kwargs.sync == true;
            this.locale = kwargs.locale || OpenSRF.locale || 'en-US';
            this.nodelay = kwargs.delay == false;

            if (this.xml && this.xml instanceof String)
                this.xml = dojox.xml.parser.parse(this.xml);

            this.mode = 'biblio-record_entry';
            this.default_datatype = 'marcxml-uris';
            if (kwargs.metarecord) {
                this.record = kwargs.metarecord;
                this.mode = 'metabib-metarecord';
                this.default_datatype = 'mods';
            }

            if (this.nodelay) this.render();
        },

        subsetNL : function (old_nl, start, end) {
            var new_nl = new dojo.NodeList();
            for (var i = start; i < end && i < old_nl.length; i++) {
                new_nl.push(old_nl[i]);
            }
            return new_nl;
        },

        textContent : function (node) {
            var content = '';
            if (node) {
                if(window.ActiveXObject) content = node.text;
                else content = node.textContent;
            }
            return content;
        },

        render : function() {

            var all_slots = dojo.query('*[type^="opac/slot-data"]', this.root);
            var default_datatype = this.default_datatype;
        
            var slots = {};
            dojo.forEach(all_slots, function(s){
                // marcxml-uris does not include copies, which avoids timeouts
                // with bib records that have hundreds or thousands of copies
                var current_datatype = default_datatype;
        
                if (s.getAttribute('datatype')) {
                    current_datatype = s.getAttribute('datatype');
                } else if (s.getAttribute('type').indexOf('+') > -1)  {
                    current_datatype = s.getAttribute('type').split('+').reverse()[0];
                }

                if (!slots[current_datatype]) slots[current_datatype] = [];
                slots[current_datatype].push(s);

            });
        
            for (var datatype in slots) {

                (function (args) {
                    var BT = args.renderer;
                    var process_record = function (bib) {
                        dojo.forEach(args.slot_list, function (slot) {
                            var debug = slot.getAttribute('debug') == 'true';

                            try {
                                var joiner = slot.getAttribute('join') || ' ';
                                var item_limit = parseInt(slot.getAttribute('limit'));
                                var item_offset = parseInt(slot.getAttribute('offset')) || 0;

                                var pre_render_callbacks = dojo.query( '*[type="opac/call-back+pre-render"]', slot );
                                var post_render_callbacks = dojo.query( '*[type="opac/call-back+post-render"]', slot );
                                var pre_query_callbacks = dojo.query( '*[type="opac/call-back+pre-query"]', slot );
                                var post_query_callbacks = dojo.query( '*[type="opac/call-back+post-query"]', slot );

                                // Do pre-query stuff
                                dojo.forEach(pre_query_callbacks, function (cb) {
                                    try { (new Function( 'BT', 'slotXML', 'slot', decodeURIComponent(cb.innerHTML) ))(BT,bib,slot) } catch (e) {/*meh*/}
                                });

                                var query = slot.getAttribute('query');
                                var xml_root = bib.documentElement || bib;

                                // Opera (as of 11.01) fails with quotes in queries
                                if (dojo.isOpera) query = query.replace(/"|'/g, '');

                                var item_list = dojo.query(
                                    query,
                                    xml_root // Make Opera work by querying from the root element
                                );

                                if (item_limit) {
                                    if (debug) alert('BibTemplate debug -- item list limit/offset requested: ' + item_limit + '/' + item_offset);
                                    if (item_list.length) item_list = BT.subsetNL(item_list, item_offset, item_offset + item_limit);
                                }

                                // Do post-query stuff
                                dojo.forEach(post_query_callbacks, function (cb) {
                                    try { (new Function( 'item_list', 'BT', 'slotXML', 'slot', decodeURIComponent(cb.innerHTML) ))(item_list,BT,bib,slot) } catch (e) {/*meh*/}
                                });

                                if (!item_list.length) return;

                                // Do pre-render stuff
                                dojo.forEach(pre_render_callbacks, function (cb) {
                                    try { (new Function( 'item_list', 'BT', 'slotXML', 'slot', decodeURIComponent(cb.innerHTML) ))(item_list,BT,bib,slot) } catch (e) {/*meh*/}
                                });

                                var templated = slot.getAttribute('templated') == 'true';
                                if (debug) alert('BibTemplate debug -- slot ' + (templated ? 'is' : 'is not') + ' templated');
                                if (templated) {
                                    if (debug) alert('BibTemplate debug -- slot template innerHTML:\n' + slot.innerHTML);
                                    var template_values = {};
                                    var template_value_count = 0;

                                    dojo.query(
                                        '*[type="opac/template-value"]',
                                        slot
                                    ).orphan().forEach(function(x) {
                                        var name = x.getAttribute('name');
                                        var value = (new Function( 'item_list', 'BT', 'slotXML', 'slot', decodeURIComponent(x.innerHTML) ))(item_list,BT,bib,slot);
                                        if (name && (value || value == '')) {
                                            template_values[name] = value;
                                            template_value_count++;
                                        }
                                    });

                                    if (debug) alert('BibTemplate debug -- template values:\n' + dojo.toJson( template_values ));
                                    if (template_value_count > 0) {
                                        dojo.attr(
                                            slot, "innerHTML",
                                            dojo.string.substitute(
                                                decodeURIComponent(slot.innerHTML),
                                                template_values
                                            )
                                        );
                                    }
                                }

                                var handler_node = dojo.query( '*[type="opac/slot-format"]', slot )[0];
                                if (handler_node) slot_handler = new Function('item_list', 'BT', 'slotXML', 'slot', 'item', dojox.xml.parser.textContent(handler_node) || handler_node.innerHTML);
                                else slot_handler = new Function('item_list', 'BT', 'slotXML', 'slot', 'item','return dojox.xml.parser.textContent(item) || item.innerHTML;');

                                if (item_list.length) {
                                    var content = dojo.map(item_list, dojo.partial(slot_handler,item_list,BT,bib,slot)).join(joiner);
                                    if (templated) {
                                        if (handler_node) handler_node.parentNode.replaceChild( dojo.doc.createTextNode( content ), handler_node );
                                    } else {
                                        dojo.attr(slot, "innerHTML", content);
                                    }
                                }

                                delete(slot_handler);

                                // Do post-render stuff
                                dojo.forEach(post_render_callbacks, function (cb) {
                                    try { (new Function( 'item_list', 'BT', 'slotXML', 'slot', decodeURIComponent(cb.innerHTML) ))(item_list,BT,bib,slot) } catch (e) {/*meh*/}
                                });

                            } catch (e) {
                                if (debug) {
                                    alert('BibTemplate Error: ' + e + '\n' + dojo.toJson(e));
                                    throw(e);
                                }
                            }
                        });
                    };

                    if (BT.xml) {
                        process_record(BT.xml);
                    } else {
                        var uri = '';
                        if (BT.tagURI) {
                            uri = BT.tagURI;
                        } else {
                            uri = 'tag:evergreen-opac:' + BT.mode + '/' + BT.record;
                            if (BT.subObjectLimit) {
                                uri += '[' + BT.subObjectLimit;
                                if (BT.subObjectOffset)
                                    uri += ',' + BT.subObjectOffset;
                                uri += ']';
                            }
                            uri += '/' + BT.org_unit;
                            if (BT.depth || BT.depth == '0') uri += '/' + BT.depth;
                        }

                        dojo.xhrGet({
                            url: '/opac/extras/unapi?id=' + uri + '&format=' + args.dtype + '&locale=' + BT.locale,
                            handleAs: 'xml',
                            sync: BT.sync,
                            preventCache: true,
                            load: process_record
                        });
                    }

                })({ slot_list : slots[datatype].reverse(), dtype : datatype, renderer : this });
            
            }

            return true;

        }
    });

    dojo._hasResource["openils.FeedTemplate"] = true;
    dojo.provide("openils.FeedTemplate");
    dojo.declare('openils.FeedTemplate', null, {

        constructor : function(kwargs) {
            this.place = kwargs.place;
            this.empty = kwargs.empty;
            this.root = kwargs.root;
            this.xml = kwargs.xml;
            this.feed_uri = kwargs.uri;
            this.item_query = kwargs.query;
            this.sync = kwargs.sync == true;
            this.preventCache = kwargs.preventCache == true;
            this.nodelay = kwargs.delay == false;
            this.reverseSort = kwargs.reverseSort == true;
            this.relativePosition = 'last';
            if (this.reverseSort) this.relativePosition = 'first';

            this.horizon = new Date().getTime();
            var horiz = parseInt(this.root.getAttribute('horizon'));

            if (isNaN(horiz) || this.horizon >= horiz) 
                this.root.setAttribute('horizon', this.horizon);

            if (this.nodelay) this.render();
        },

        render : function () {
            var me = this;

            var process_feed = function (xmldoc) {
		if (parseInt(me.horizon) >= parseInt(me.root.getAttribute('horizon'))) {
                    if (me.empty == true) dojo.empty(me.place);
                    me.root.setAttribute('horizon', this.horizon);
                    dojo.query( me.item_query, xmldoc ).forEach(
                        function (item) {
                            var template = me.root.cloneNode(true);
                            dojo.place( template, me.place, me.relativePosition );
                            new openils.BibTemplate({ delay : false, xml : item, root : template });
                        }
                    );
                }
            };

            if (this.xml) {
                process_feed(this.xml);
            } else {
                dojo.xhrGet({
                    url: me.feed_uri,
                    handleAs: 'xml',
                    sync: me.sync,
                    preventCache: me.preventCache,
                    load: process_feed
                });
            }

        }
    });
}
