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

if(!dojo._hasResource["MARC.Record"]) {

    dojo.require('dojox.xml.parser');
    dojo.require('MARC.Field');

    dojo._hasResource["MARC.Record"] = true;
    dojo.provide("MARC.Record");
    dojo.declare('MARC.Record', null, {

        delimiter : '\u2021', // default subfield delimiter

        constructor : function(kwargs) {
            this.fields = [];
            this.leader = '';

            if (kwargs.delimiter) this.delimiter = kwargs.delimiter;
            if (kwargs.onLoad) this.onLoad = kwargs.onLoad;
            if (kwargs.url) {
                this.fromXmlURL(kwargs.url);
            } else if (kwargs.marcxml) {
                this.fromXmlString(kwargs.marcxml);
                if (this.onLoad) this.onLoad();
            } else if (kwargs.xml) {
                this.fromXmlDocument(kwargs.xml);
                if (this.onLoad) this.onLoad();
            } else if (kwargs.marcbreaker) {
                this.fromBreaker(kwargs.marcbreaker);
                if (this.onLoad) this.onLoad();
            }
        },

        title : function () { return this.subfield('245','a') },

        field : function (spec) {
            var list = dojo.filter( this.fields, function (f) {
                if (f.tag.match(spec)) return true;
                return false;
            });

            if (list.length == 1) return list[0];
            return list;
        },

        subfield : function (spec, code) { return this.field(spec)[0].subfield(code) },

        appendFields : function () {
            var me = this;
            dojo.forEach( arguments, function (f) { me.fields.push( f ) } );
        },

        deleteField : function (f) { return this.deleteFields(f) },

        insertOrderedFields : function () {
            var me = this;
            for ( var i in arguments ) {
                var f = arguments[i];
                for (var j in this.fields) {
                    if (f.tag > this.fields[j].tag) {
                        this.insertFieldsBefore(this.fields[j], f);
                        break;
                    }
                }
            }
        },

        insertFieldsBefore : function (target) {
            arguments.splice(0,1);
            var me = this;
            for (var j in this.fields) {
                if (target === this.fields[j]) {
                    j--;
                    dojo.forEach( arguments, function (f) {
                        me.fields.splice(j++,0,f);
                    });
                    break;
                }
            }
        },

        insertFieldsAfter : function (target) {
            arguments.splice(0,1);
            var me = this;
            for (var j in this.fields) {
                if (target === this.fields[j]) {
                    dojo.forEach( arguments, function (f) {
                        me.fields.splice(j++,0,f);
                    });
                    break;
                }
            }
        },

        deleteFields : function () {
            var me = this;
            var counter = 0;
            for ( var i in arguments ) {
                var f = arguments[i];
                for (var j in me.fields) {
                    if (f === me.fields[j]) {
                        me.fields[j].record = null;
                        me.fields.splice(j,0);
                        counter++
                        break;
                    }
                }
            }
            return counter;
        },

        clone : function () { return dojo.clone(this) },

        fromXmlURL : function (url) {
            this.ready   = false;
            var me = this;
            dojo.xhrGet({
                url     : url,
                sync    : true,
                handleAs: 'xml',
                load    : function (mxml) {
                    me.fromXmlDocument(dojo.query('record', mxml)[0]);
                    me.ready = true;
                    if (me.onLoad) me.onLoad();
                }
            });
        },

        fromXmlString : function (mxml) {
                return this.fromXmlDocument( dojox.xml.parser.parse( mxml ) );
        },

        fromXmlDocument : function (mxml) {
            var me = this;
            me.leader = dojox.xml.parser.textContent(dojo.query('leader', mxml)[0]) || '';

            dojo.forEach( dojo.query('controlfield', mxml), function (cf) {
                me.fields.push(
                    new MARC.Field({
                          record : me,
                          tag    : cf.getAttribute('tag'),
                          data   : dojox.xml.parser.textContent(cf)
                    })
                )
            });

            dojo.forEach( dojo.query('datafield', mxml), function (df) {
                me.fields.push(
                    new MARC.Field({
                        record    : me,
                        tag       : df.getAttribute('tag'),
                        ind1      : df.getAttribute('ind1'),
                        ind2      : df.getAttribute('ind2'),
                        subfields : dojo.map(
                            dojo.query('subfield', df),
                            function (sf) {
                                return [ sf.getAttribute('code'), dojox.xml.parser.textContent(sf) ];
                            }
                        )
                    })
                )
            });

            return this;
        },

        toXmlDocument : function () {

            var doc = dojox.xml.parser.parse('<record xmlns="http://www.loc.gov/MARC21/slim"/>');
            var rec_node = dojo.query('record', doc)[0];

            var ldr = doc.createElementNS('http://www.loc.gov/MARC21/slim', 'leader');
            dojox.xml.parser.textContent(ldr, this.leader);
            rec_node.appendChild( ldr );

            dojo.forEach( this.fields, function (f) {
                var element = f.isControlfield() ? 'controlfield' : 'datafield';
                var f_node = doc.createElementNS( 'http://www.loc.gov/MARC21/slim', element );
                f_node.setAttribute('tag', f.tag);
                
                if (f.isControlfield() && f.data) {
                    dojox.xml.parser.textContent(f_node, f.data);
                } else {
                    f_node.setAttribute('ind1', f.indicator(1));
                    f_node.setAttribute('ind2', f.indicator(2));
                    dojo.forEach( f.subfields, function (sf) {
                        var sf_node = doc.createElementNS('http://www.loc.gov/MARC21/slim', 'subfield');
                        sf_node.setAttribute('code', sf[0]);
                        dojox.xml.parser.textContent(sf_node, sf[1]);
                        f_node.appendChild(sf_node);
                    });
                }

                rec_node.appendChild(f_node);
            });

            return doc;
        },

        toXmlString : function () {
            return dojox.xml.parser.innerXML( this.toXmlDocument() );
        },

        fromBreaker : function (marctxt) {
            var me = this;

            function cf_line_data (l) { return l.substring(4) };
            function df_line_data (l) { return l.substring(6) };
            function line_tag (l) { return l.substring(0,3) };
            function df_ind1 (l) { return l.substring(4,5).replace('\\',' ') };
            function df_ind2 (l) { return l.substring(5,6).replace('\\',' ') };
            function isControlField (l) {
                var x = line_tag(l);
                return (x == 'LDR' || x < '010') ? true : false;
            }
            
            var lines = marctxt.replace(/^=/gm,'').split('\n');
            dojo.forEach(lines, function (current_line) {

                if (current_line.match(/^#/)) {
                    // skip comment lines
                } else if (isControlField(current_line)) {
                    if (line_tag(current_line) == 'LDR') {
                        me.leader = cf_line_data(current_line) || '';
                    } else {
                        me.fields.push(
                            new MARC.Field({
                                record : me,
                                tag    : line_tag(current_line),
                                data   : cf_line_data(current_line).replace('\\',' ','g')
                            })
                        );
                    }
                } else {
                    var data = df_line_data(current_line);
                    var start_delim = new RegExp( '^' + me.delimiter );
                    if (!data.match( start_delim )) data = me.delimiter + 'a' + data;

                    var sf_list = data.split(me.delimiter);
                    sf_list.shift();

                    me.fields.push(
                        new MARC.Field({
                                record    : me,
                                tag       : line_tag(current_line),
                                ind1      : df_ind1(current_line),
                                ind2      : df_ind2(current_line),
                                subfields : dojo.map(
                                    sf_list,
                                    function (sf) { return [ sf.substring(0,1), sf.substring(1) ] }
                                )
                        })
                    );
                }
            });

            return this;
        },

        toBreaker : function () {

            var me = this;
            var mtxt = '=LDR ' + this.leader + '\n';

            mtxt += dojo.map( this.fields, function (f) {
                if (f.isControlfield() && f.data) {
                    return '=' + f.tag + ' ' + f.data.replace(' ','\\','g');
                } else {
                    return '=' + f.tag + ' ' +
                        f.indicator(1).replace(' ','\\') + 
                        f.indicator(2).replace(' ','\\') + 
                        dojo.map( f.subfields, function (sf) {
                            return me.delimiter + sf.join('');
                        }).join('');
                }
            }).join('\n');

            return mtxt;
        }
    });
}
