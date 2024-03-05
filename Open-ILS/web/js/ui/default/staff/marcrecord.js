/* ---------------------------------------------------------------------------
 * Copyright (C) 2009-2015  Equinox Software, Inc.
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

// !!! Head's up !!!
// This module requires a /real/ jQuery be used with your
// angularjs, so as to avoid using hand-rolled AJAX.

var MARC21 = {

    Record : function(kwargs) {
        if (!kwargs) kwargs = {};

        this.generate008 = function () {
            var f;
            var s;
            var orig008 = '                                        ';
            var now = new Date();
            var y = now.getUTCFullYear().toString().substr(2,2);
            var m = now.getUTCMonth() + 1;
            if (m < 10) m = '0' + m;
            var d = now.getUTCDate();
            if (d < 10) d = '0' + d;


            if (f = this.field('008',true)[0]) {
                orig008 = f.data;
            }
        
            /* lang code from 041a */
            var lang = orig008.substr(35, 3);
            
            if (f = this.field('041',true)[0]) {
                if (s = f.subfield('a',true)[0]) {
                    if(s[1]) lang = s[1];
                }
            }
        
            /* country code from 044a */
            var country = orig008.substr(15, 3);
            if (f = this.field('044',true)[0]) {
                if (s = f.subfield('a',true)[0]) {
                    if(s[1]) country = s[1];
                }
            }
            while (country.length < 3) country = country + ' ';
            if (country.length > 3) country = country.substr(0,3);
        
            /* date1 from 260c */
            var date1 = now.getUTCFullYear().toString();
            if (f = this.field('260',true)[0]) {
                if (s = f.subfield('c',true)[0]) {
                    if (s[1]) {
                        var tmpd = s[1];
                        tmpd = tmpd.replace(/[^0-9]/g, '');
                        if (tmpd.match(/^\d\d\d\d/)) {
                            date1 = tmpd.substr(0, 4);
                        }
                    }
                }
            }
        
            var date2 = orig008.substr(11, 4);
            var datetype = orig008.substr(6, 1);
            var modded = orig008.substr(38, 1);
            var catsrc = orig008.substr(39, 1);
        
            return '' + y + m + d + datetype + date1 + date2 + country + '                 ' + lang + modded + catsrc;
        
        }

        this.title = function () { return this.subfield('245','a')[1] }

        this.field = function (spec, wantarray) {
            var list = this.fields.filter(function (f) {
                if (f.tag.match(spec)) return true;
                return false;
            });

            if (!wantarray && list.length == 1) return list[0];
            return list;
        }

        this.subfield = function (spec, code) {
            var f = this.field(spec, true)[0];
            if (f) return f.subfield(code)
            return null;
        }

        this.appendFields = function () {
            var me = this;
            Array.prototype.slice.call(arguments).forEach( function (f) { f.position = me.fields.length; me.fields.push( f ) } );
        }

        this.deleteField = function (f) { return this.deleteFields(f) },

        this.insertOrderedFields = function () {
            var me = this;
            for (var i = 0; i < arguments.length; i++) {
                var f = arguments[i];
                var done = false;
                for (var j = 0; j < this.fields.length; j++) {
                    if (f.tag < this.fields[j].tag) {
                        this.insertFieldsBefore(this.fields[j], f);
                        done = true;
                        break;
                    }
                }
                if (!done) this.appendFields(f);
            }
        }

        this.insertFieldsBefore = function (target) {
            var args = Array.prototype.slice.call(arguments);
            args.splice(0,1);
            var me = this;
            for (var j = 0; j < this.fields.length; j++) {
                if (target === this.fields[j]) {
                    args.forEach( function (f) {
                        f.record = me;
                        me.fields.splice(j++,0,f);
                    });
                    break;
                }
            }
            for (var j = 0; j < this.fields.length; j++) {
                this.fields[j].position = j;
            }
        }

        this.insertFieldsAfter = function (target) {
            var args = Array.prototype.slice.call(arguments);
            args.splice(0,1);
            var me = this;
            for (var j = 0; j < this.fields.length; j++) {
                if (target === this.fields[j]) {
                    args.forEach( function (f) {
                        f.record = me;
                        me.fields.splice(++j,0,f);
                    });
                    break;
                }
            }
            for (var j = 0; j < this.fields.length; j++) {
                this.fields[j].position = j;
            }
        }

        this.deleteFields = function () {
            var me = this;
            var counter = 0;
            for ( var i in arguments ) {
                var f = arguments[i];
                for (var j = 0; j < me.fields.length; j++) {
                    if (f === me.fields[j]) {
                        me.fields[j].record = null;
                        me.fields.splice(j,1);
                        counter++
                        break;
                    }
                }
            }
            for (var j = 0; j < this.fields.length; j++) {
                this.fields[j].position = j;
            }
            return counter;
        }

        // this.clone = function () { return dojo.clone(this) } // maybe implement later...

        this.fromXmlURL = function (url) {
            var me = this;
            return $.get( // This is a Promise
                url,
                function (mxml) {
                    me.fromXmlDocument($('record', mxml)[0]);
                    if (me.onLoad) me.onLoad();
            });
        }

        this.fromXmlString = function (mxml) {
                this.fromXmlDocument( $( $.parseXML( mxml ) ).find('record')[0] );
        }

        this.fromXmlDocument = function (mxml) {
            var me = this;
            me.leader = $($('leader',mxml)[0]).text() || '00000cam a2200205Ka 4500';

            $('controlfield', mxml).each(function (ind) {
                var cf=$(this);
                me.fields.push(
                    new MARC21.Field({
                          record : me,
                          tag    : cf.attr('tag'),
                          data   : cf.text(),
                    })
                )
            });

            $('datafield', mxml).each(function (ind) {
                var df=$(this);
                me.fields.push(
                    new MARC21.Field({
                        record    : me,
                        tag       : df.attr('tag'),
                        ind1      : df.attr('ind1'),
                        ind2      : df.attr('ind2'),
                        subfields : $('subfield', df).map(
                            function (i, sf) {
                                return [[ $(sf).attr('code'), $(sf).text(), i ]];
                            }
                        ).get()
                    })
                )
            });

            for (var j = 0; j < this.fields.length; j++) {
                this.fields[j].position = j;
            }

            me.ready = true;

        }

        this.toXmlDocument = function () {

            var doc = $.parseXML('<record xmlns="http://www.loc.gov/MARC21/slim"/>');
            var rec_node = $('record', doc)[0];

            var ldr = doc.createElementNS('http://www.loc.gov/MARC21/slim', 'leader');
            ldr.textContent = this.leader;
            rec_node.appendChild( ldr );

            this.fields.forEach(function (f) {
                var element = f.isControlfield() ? 'controlfield' : 'datafield';
                var f_node = doc.createElementNS( 'http://www.loc.gov/MARC21/slim', element );
                f_node.setAttribute('tag', f.tag);
                
                if (f.isControlfield()) {
                    if (f.data) f_node.textContent = f.data;
                } else {
                    f_node.setAttribute('ind1', f.indicator(1));
                    f_node.setAttribute('ind2', f.indicator(2));
                    f.subfields.forEach( function (sf) {
                        var sf_node = doc.createElementNS('http://www.loc.gov/MARC21/slim', 'subfield');
                        sf_node.setAttribute('code', sf[0]);
                        sf_node.textContent = sf[1];
                        f_node.appendChild(sf_node);
                    });
                }

                rec_node.appendChild(f_node);
            });

            return doc;
        }

        this.toXmlString = function () {
            return (new XMLSerializer()).serializeToString( this.toXmlDocument() );
        }

        this.fromBreaker = function (marctxt) {
            var me = this;

            function cf_line_data (l) { return l.substring(4) || '' };
            function df_line_data (l) { return l.substring(6) || '' };
            function line_tag (l) { return l.substring(0,3) };
            function df_ind1 (l) { return l.substring(4,5).replace('\\',' ') };
            function df_ind2 (l) { return l.substring(5,6).replace('\\',' ') };
            function isControlField (l) {
                var x = line_tag(l);
                return (x == 'LDR' || x < '010') ? true : false;
            }
            
            var lines = marctxt.replace(/^=/gm,'').split('\n');
            lines.forEach(function (current_line, ind) {

                if (current_line.match(/^#/)) {
                    // skip comment lines
                } else if (isControlField(current_line)) {
                    if (line_tag(current_line) == 'LDR') {
                        me.leader = cf_line_data(current_line) || '00000cam a2200205Ka 4500';
                    } else {
                        me.fields.push(
                            new MARC21.Field({
                                record : me,
                                tag    : line_tag(current_line),
                                data   : cf_line_data(current_line).replace(/\\/g, ' ')
                            })
                        );
                    }
                } else {
                    if (current_line.substring(4,5) == me.delimiter) // add indicators if they were left out
                        current_line = current_line.substring(0,3) + ' \\\\' + current_line.substring(4);

                    var data = df_line_data(current_line);
                    if (!(data.substring(0,1) == me.delimiter)) data = me.delimiter + 'a' + data;

                    var local_delimiter = me.delimiter;
                    if (data.indexOf('\u2021') > -1)
                        local_delimiter = '\u2021';

                    var sf_list = data.split(local_delimiter);
                    sf_list.shift();

                    me.fields.push(
                        new MARC21.Field({
                                record    : me,
                                tag       : line_tag(current_line),
                                ind1      : df_ind1(current_line),
                                ind2      : df_ind2(current_line),
                                subfields : sf_list.map( function (sf, i) {
                                                var sf_data = sf.substring(1);
                                                if (local_delimiter == '$') sf_data = sf_data.replace(/\{dollar\}/g, '$');
                                                return [ sf.substring(0,1), sf_data, i ];
                                            })
                        })
                    );
                }
            });

            for (var j = 0; j < this.fields.length; j++) {
                this.fields[j].position = j;
            }

            me.ready = true;
            return this;
        }

        this.pruneEmptyFieldsAndSubfields = function() {
            var me = this;
            var fields_to_remove = [];
            for (var i = 0; i < this.fields.length; i++) {
                var f = this.fields[i];
                if (f.isControlfield()) {
                    if (!f.data){
                        fields_to_remove.push(f);
                    }
                } else {
                    f.pruneEmptySubfields();
                    if (f.isEmptyDatafield()) {
                        fields_to_remove.push(f);
                    }
                }
            }
            fields_to_remove.forEach(function(f) {
                me.deleteField(f);
            });
        }

        this.toBreaker = function () {

            var me = this;
            var mtxt = '=LDR ' + this.leader + '\n';

            mtxt += this.fields.map( function (f) {
                if (f.isControlfield()) {
                    if (f.data) return '=' + f.tag + ' ' + f.data.replace(/ /g, '\\');
                    return '=' + f.tag;
                } else {
                    return '=' + f.tag + ' ' +
                        f.indicator(1).replace(' ','\\') + 
                        f.indicator(2).replace(' ','\\') + 
                        f.subfields.map( function (sf) {
                            var sf_data = sf[1];
                            if (me.delimiter == '$') sf_data = sf_data.replace(/\$/g, '{dollar}');
                            return me.delimiter + sf[0] + sf_data;
                        }).join('');
                }
            }).join('\n');

            return mtxt;
        }

        this.recordType = function () {
        
            var _t = this.leader.substr(MARC21.Record._ff_pos.Type.ldr.BKS.start, MARC21.Record._ff_pos.Type.ldr.BKS.len);
            var _b = this.leader.substr(MARC21.Record._ff_pos.BLvl.ldr.BKS.start, MARC21.Record._ff_pos.BLvl.ldr.BKS.len);
        
            for (var t in MARC21.Record._recType) {
                if (_t.match(MARC21.Record._recType[t].Type) && _b.match(MARC21.Record._recType[t].BLvl)) {
                    return t;
                }
            }
            return 'BKS'; // default
        }
        
        this.videorecordingFormatName = function () {
            var _7 = this.field('007').data;
        
            if (_7 && _7.match(/^v/)) {
                var _v_e = _7.substr(
                    MARC21.Record._physical_characteristics.v.subfields.e.start,
                    MARC21.Record._physical_characteristics.v.subfields.e.len
                );
        
                return MARC21.Record._physical_characteristics.v.subfields.e.values[ _v_e ];
            }
        
            return null;
        }
        
        this.videorecordingFormatCode = function () {
            var _7 = this.field('007').data;
        
            if (_7 && _7.match(/^v/)) {
                return _7.substr(
                    MARC21.Record._physical_characteristics.v.subfields.e.start,
                    MARC21.Record._physical_characteristics.v.subfields.e.len
                );
            }
        
            return null;
        }
        
        this.extractFixedField = function (field, dflt) {
        if (!MARC21.Record._ff_pos[field]) return null;
        
            var _l = this.leader;
            var _8 = this.field('008').data;
            var _6 = this.field('006').data;
        
            var rtype = this.recordType();
        
            var val;
        
            if (MARC21.Record._ff_pos[field].ldr && _l) {
                if (MARC21.Record._ff_pos[field].ldr[rtype]) {
                    val = _l.substr(
                        MARC21.Record._ff_pos[field].ldr[rtype].start,
                        MARC21.Record._ff_pos[field].ldr[rtype].len
                    );
                }
            } else if (MARC21.Record._ff_pos[field]._8 && _8) {
                if (MARC21.Record._ff_pos[field]._8[rtype]) {
                    val = _8.substr(
                        MARC21.Record._ff_pos[field]._8[rtype].start,
                        MARC21.Record._ff_pos[field]._8[rtype].len
                    );
                }
            }
        
            if (!val && MARC21.Record._ff_pos[field]._6 && _6) {
                if (MARC21.Record._ff_pos[field]._6[rtype]) {
                    val = _6.substr(
                        MARC21.Record._ff_pos[field]._6[rtype].start,
                        MARC21.Record._ff_pos[field]._6[rtype].len
                    );
                }
            }
    
            if (!val && dflt) {
                val = '';
                var d;
                var p;
                if (MARC21.Record._ff_pos[field].ldr && MARC21.Record._ff_pos[field].ldr[rtype]) {
                    d = MARC21.Record._ff_pos[field].ldr[rtype].def;
                    p = 'ldr';
                }
    
                if (MARC21.Record._ff_pos[field]._8 && MARC21.Record._ff_pos[field]._8[rtype]) {
                    d = MARC21.Record._ff_pos[field]._8[rtype].def;
                    p = '_8';
                }
    
                if (!val && MARC21.Record._ff_pos[field]._6 && MARC21.Record._ff_pos[field]._6[rtype]) {
                    d = MARC21.Record._ff_pos[field]._6[rtype].def;
                    p = '_6';
                }
    
                if (p) {
                    for (var j = 0; j < MARC21.Record._ff_pos[field][p][rtype].len; j++) {
                        val += d;
                    }
                } else {
                    val = null;
                }
            }
    
            return val;
        }
    
        this.setFixedField = function (field, value) {
            if (!MARC21.Record._ff_pos[field]) return null;
        
            var _l = this.leader;
            var _8 = this.field('008').data;
            var _6 = this.field('006').data;
        
            var rtype = this.recordType();
        
            var done = false;
            if (MARC21.Record._ff_pos[field].ldr && _l) {
                if (MARC21.Record._ff_pos[field].ldr[rtype]) { // It's in the leader
                    if (value.length > MARC21.Record._ff_pos[field].ldr[rtype].len)
                        value = value.substr(0, MARC21.Record._ff_pos[field].ldr[rtype].len);
                    while (value.length < MARC21.Record._ff_pos[field].ldr[rtype].len)
                        value += MARC21.Record._ff_pos[field].ldr[rtype].def;
                    this.leader =
                        _l.substring(0, MARC21.Record._ff_pos[field].ldr[rtype].start) +
                        value +
                        _l.substring(
                            MARC21.Record._ff_pos[field].ldr[rtype].start
                            + MARC21.Record._ff_pos[field].ldr[rtype].len
                        );
                    done = true;
                }
            } else if (MARC21.Record._ff_pos[field]._8 && _8) {
                if (MARC21.Record._ff_pos[field]._8[rtype]) { // Nope, it's in the 008
                    if (value.length > MARC21.Record._ff_pos[field]._8[rtype].len)
                        value = value.substr(0, MARC21.Record._ff_pos[field]._8[rtype].len);
                    while (value.length < MARC21.Record._ff_pos[field]._8[rtype].len)
                        value += MARC21.Record._ff_pos[field]._8[rtype].def;

                    // first ensure that 008 is padded to appropriate length
                    var f008_length = (rtype in MARC21.Record._ff_lengths['008']) ?
                        MARC21.Record._ff_lengths['008'][rtype] :
                        MARC21.Record._ff_lengths['008']['default'];
                    if (_8.length < f008_length) {
                        for (var i = _8.length; i < f008_length; i++) {
                            _8 += ' ';
                        }
                    }
                    this.field('008').update(
                        _8.substring(0, MARC21.Record._ff_pos[field]._8[rtype].start) +
                        value +
                        _8.substring(
                            MARC21.Record._ff_pos[field]._8[rtype].start
                            + MARC21.Record._ff_pos[field]._8[rtype].len
                        )
                    );
                    done = true;
                }
            }
        
            if (!done && MARC21.Record._ff_pos[field]._6 && _6) {
                if (MARC21.Record._ff_pos[field]._6[rtype]) { // ok, maybe the 006?
                    if (value.length > MARC21.Record._ff_pos[field]._6[rtype].len)
                        value = value.substr(0, MARC21.Record._ff_pos[field]._6[rtype].len);
                    while (value.length < MARC21.Record._ff_pos[field]._6[rtype].len)
                        value += MARC21.Record._ff_pos[field]._6[rtype].def;
                    this.field('006').update(
                        _6.substring(0, MARC21.Record._ff_pos[field]._6[rtype].start) +
                        value +
                        _6.substring(
                            MARC21.Record._ff_pos[field]._6[rtype].start
                            + MARC21.Record._ff_pos[field]._6[rtype].len
                        )
                    );
                }
            }
    
            return value;
        }

        this.ready = false;
        this.fields = [];
        this.delimiter = MARC21.Record.delimiter ? MARC21.Record.delimiter : '\u2021';
        this.leader = '00000cam a2200205Ka 4500';

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

        if (kwargs.rtype == 'AUT') {
            this.setFixedField('Type','z');
        }

    },

    Field : function (kwargs) {
        if (!kwargs) kwargs = {};

        this.subfield = function (code, wantarray) {
            var list = this.subfields.filter( function (s) {
                if (s[0] == code) return true; return false;
            });
            if (!wantarray && list.length == 1) return list[0];
            return list;
        }

        this.addSubfields = function () {
            for (var i = 0; i < arguments.length; i++) {
                var code = arguments[i];
                var value = arguments[++i];
                this.subfields.push( [ code, value ] );
            }
        }

        this.deleteExactSubfields = function () {
            var me = this;
            var counter = 0;
            var done = false;
            for ( var i in arguments ) {
                var f = arguments[i];
                for (var j = 0; j < me.subfields.length; j++) {
                    if (f === me.subfields[j]) {
                        me.subfields.splice(j,1);
                        counter++
                        j++;
                        done = true;
                    }
                    if (done && me.subfields[j])
                        me.subfields[j][2] -= 1;
                }
            }
            return counter;
        }


        this.deleteSubfields = function (c) {
            return this.deleteSubfield( { code : c } );
        }

        this.deleteSubfield = function (args) {
            var me = this;
            if (!Array.isArray( args.code )) {
                args.code = [ args.code ];
            }

            if (args.pos && !Array.isArray( args.pos )) {
                args.pos = [ args.pos ];
            }

            for (var i = 0; i < args.code.length; i++) {
                var sub_pos = {};
                for (var j = 0; j < me.subfields.length; j++) {
                    if (me.subfields[j][0] == args.code[i]) {

                        if (!sub_pos[args.code[i]]) sub_pos[args.code[j]] = 0;
                        else sub_pos[args.code[i]]++;

                        if (args.pos) {
                            for (var k = 0; k < args.pos.length; k++) {
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
        }

        this.update = function ( args ) {
            if (this.isControlfield()) {
                this.data = args;
            } else {
                if (args.ind1) this.ind1 = args.ind1;
                if (args.ind2) this.ind2 = args.ind2;
                if (args.tag) this.tag = args.tag;

                for (var i in args) {
                    if (i == 'tag' || i == 'ind1' || i == 'ind2') continue;
                    var done = 0;
                    this.subfields.forEach( function (f) {
                        if (!done && f[0] == i) {
                            f[1] = args[i];
                            done = 1;
                        }
                    });
                }
            }
        }

        this.isControlfield = function () {
            return this.tag < '010' ? true : false;
        }

        this.pruneEmptySubfields = function () {
            if (this.isControlfield()) return;
            var me = this;
            var subfields_to_remove = [];
            this.subfields.forEach( function(f) {
                if (f[1] == '') {
                    subfields_to_remove.push(f);
                }
            });
            subfields_to_remove.forEach(function(f) {
                me.deleteExactSubfields(f);
            });
        }
        this.isEmptyDatafield = function () {
            if (this.isControlfield()) return false;
            var isEmpty = true;
            this.subfields.forEach( function(f) {
                if (isEmpty && f[1] != '') {
                    isEmpty = false;
                }
            });
            return isEmpty;
        }

        this.indicator = function (num, value) {
            if (value !== undefined) {
                if (num == 1) this.ind1 = value;
                else if (num == 2) this.ind2 = value;
                else { this.error = true; return null; }
            }
            if (num == 1) return this.ind1;
            else if (num == 2) return this.ind2;
            else { this.error = true; return null; }
        }

        this.error = false; 
        this.record = null; // MARC record pointer
        this.tag = ''; // MARC tag
        this.ind1 = ' '; // MARC indicator 1
        this.ind2 = ' '; // MARC indicator 2
        this.data = ''; // MARC data for a controlfield element
        this.subfields = []; // list of MARC subfields for a datafield element

        this.position = kwargs.position;
        this.record = kwargs.record;
        this.tag = kwargs.tag;
        this.ind1 = kwargs.ind1 || ' ';
        this.ind2 = kwargs.ind2 || ' ';
        this.data = kwargs.data;

        if (kwargs.subfields) this.subfields = kwargs.subfields;
        else this.subfields = [];

    },

    Batch : function(kwargs) {

        this.parse = function () {
            if (this.source instanceof Object ) { // assume an xml collection document
                this.source = $('record', this.source);
                this.type = 'xml';
            } else if (this.source.match(/^\s*</)) { // this is xml text
                this.source = $.parseXML( mxml ).find('record');
                this.type = 'xml';
            } else { // must be a marcbreaker doc. split on blank lines
                this.source = this.source.split(/^$/);
                this.type = 'marcbreaker';
            }
        }

        this.fetchURL = function (u) {
            var me = this;
            $.get( u, function (mrc) {
                me.source = mrc;
                me.ready = true;
            });
        }

        this.next = function () {
            var chunk = this.source[this.current_record++];

            if (chunk) {
                var args = {};
                args[this.type] = chunk;
                if (this.delimiter) args.delimiter = this.delimiter;
                return new MARC21.Record(args);
            }

            return null;
        }

        this.ready = false;
        this.records = [];
        this.source = kwargs.source;
        this.delimiter = kwargs.delimiter
        this.current_record = 0;

        if (this.source) this.ready = true;
        if (!this.ready && kwargs.url) this.fetchURL( kwargs.url );

        if (this.ready) this.parse();

    },

    AuthorityControlSet : function (kwargs) {
    
        kwargs = kwargs || {};
    
        if (!MARC21.AuthorityControlSet._remote_loaded) {
    
            // TODO -- push the raw tree into the oils cache for later reuse
    
            // fetch everything up front...
            this._preFetchWithFielder({
                "acs": "_control_set_list",
                "at": "_thesaurus_list",
                "acsaf": "_authority_field_list",
                "acsbf": "_bib_field_list",
                "aba": "_browse_axis_list",
                "abaafm": "_browse_field_map_list"
            });
    
            MARC21.AuthorityControlSet._remote_loaded = true;
        }
    
        if (MARC21.AuthorityControlSet._remote_loaded && !MARC21.AuthorityControlSet._remote_parsed) {
    
            MARC21.AuthorityControlSet._browse_axis_by_code = {};
            MARC21.AuthorityControlSet._browse_axis_list.forEach(function (ba) {
                ba.maps(
                    MARC21.AuthorityControlSet._browse_field_map_list.filter(
                        function (m) { return m.axis() == ba.code() }
                    )
                );
                MARC21.AuthorityControlSet._browse_axis_by_code[ba.code()] = ba;
            });
    
            // loop over each acs
            MARC21.AuthorityControlSet._control_set_list.forEach(function (cs) {
                MARC21.AuthorityControlSet._controlsets[''+cs.id()] = {
                    id : cs.id(),
                    name : cs.name(),
                    description : cs.description(),
                    authority_tag_map : {},
                    control_map : {},
                    bib_fields : [],
                    raw : cs
                };
    
                // grab the authority fields
                var acsaf_list = MARC21.AuthorityControlSet._authority_field_list.filter(
                    function (af) { return af.control_set() == cs.id() }
                );
    
                var at_list = MARC21.AuthorityControlSet._thesaurus_list.filter(
                    function (at) { return at.control_set() == cs.id() }
                );
    
                MARC21.AuthorityControlSet._controlsets[''+cs.id()].raw.authority_fields( acsaf_list );
                MARC21.AuthorityControlSet._controlsets[''+cs.id()].raw.thesauri( at_list );
    
                // and loop over each
                acsaf_list.forEach(function (csaf) {
                    csaf.axis_maps([]);
    
                    // link the main entry if we're subordinate
                    if (csaf.main_entry()) {
                        csaf.main_entry(
                            acsaf_list.filter(function (x) {
                                return x.id() == csaf.main_entry();
                            })[0]
                        );
                    }
    
                    // link the sub entries if we're main
                    csaf.sub_entries(
                        acsaf_list.filter(function (x) {
                            return x.main_entry() == csaf.id();
                        })
                    );
    
                    // now, bib fields
                    var acsbf_list = MARC21.AuthorityControlSet._bib_field_list.filter(
                        function (b) { return b.authority_field() == csaf.id() }
                    );
                    csaf.bib_fields( acsbf_list );
    
                    MARC21.AuthorityControlSet._controlsets[''+cs.id()].bib_fields = [].concat(
                        MARC21.AuthorityControlSet._controlsets[''+cs.id()].bib_fields,
                        acsbf_list
                    );
    
                    acsbf_list.forEach(function (csbf) {
                        // link the authority field to the bib field
                        if (csbf.authority_field()) {
                            csbf.authority_field(
                                acsaf_list.filter(function (x) {
                                    return x.id() == csbf.authority_field();
                                })[0]
                            );
                        }
    
                    });
    
                    MARC21.AuthorityControlSet._browse_axis_list.forEach(
                        function (ba) {
                            ba.maps().filter(
                                function (m) { return m.field() == csaf.id() }
                            ).forEach(
                                function (fm) { fm.field( csaf ); csaf.axis_maps().push( fm ) } // and set the field
                            )
                        }
                    );
    
                });
    
                // build the authority_tag_map
                MARC21.AuthorityControlSet._controlsets[''+cs.id()].bib_fields.forEach(function (bf) {
    
                    if (!MARC21.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()])
                        MARC21.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()] = {};
    
                    bf.authority_field().sf_list().split('').forEach(function (sf_code) {
    
                        if (!MARC21.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()][sf_code])
                            MARC21.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()][sf_code] = {};
    
                        MARC21.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()][sf_code][bf.authority_field().tag()] = sf_code;
                    });
                });
    
            });
    
            if (this.controlSetList().length > 0)
                delete MARC21.AuthorityControlSet._controlsets['-1'];
    
            MARC21.AuthorityControlSet._remote_parsed = true;
        }
    
        this._preFetchWithFielder = function(cmap) {
            for (var hint in cmap) {
                var cache_key = cmap[hint];
                var method = "open-ils.fielder." + hint + ".atomic";
                var pkey = fieldmapper.IDL.fmclasses[hint].pkey;
    
                var query = {};
                query[pkey] = {"!=": null};
    
                MARC21.AuthorityControlSet[cache_key] = dojo.map(
                    fieldmapper.standardRequest(
                        ["open-ils.fielder", method],
                        [{"cache": 1, "query" : query}]
                    ),
                    function(h) { return new fieldmapper[hint]().fromHash(h); }
                );
            }
        }
    
        this.controlSetId = function (x) {
            if (x) this._controlset = ''+x;
            return this._controlset;
        }
    
        this.controlSet = function (x) {
            return MARC21.AuthorityControlSet._controlsets[''+this.controlSetId(x)];
        }
    
        this.controlSetByThesaurusCode = function (x) {
            var thes = MARC21.AuthorityControlSet._thesaurus_list.filter(
                function (at) { return at.code() == x }
            )[0];
    
            return this.controlSet(thes.control_set());
        }
    
        this.browseAxisByCode = function(code) {
            return MARC21.AuthorityControlSet._browse_axis_by_code[code];
        }
    
        this.bibFieldByTag = function (x) {
            var me = this;
            return me.controlSet().bib_fields.filter(
                function (bf) { if (bf.tag() == x) return true }
            )[0];
        }
    
        this.bibFields = function (x) {
            return this.controlSet(x).bib_fields;
        }
    
        this.bibFieldBrowseAxes = function (t) {
            var blist = [];
            for (var bcode in MARC21.AuthorityControlSet._browse_axis_by_code) {
                MARC21.AuthorityControlSet._browse_axis_by_code[bcode].maps().forEach(
                    function (m) {
                        if (m.field().bib_fields().filter(
                                function (b) { return b.tag() == t }
                            ).length > 0
                        ) blist.push(bcode);
                    }
                );
            }
            return blist;
        }
    
        this.authorityFields = function (x) {
            return this.controlSet(x).raw.authority_fields();
        }
    
        this.thesauri = function (x) {
            return this.controlSet(x).raw.thesauri();
        }
    
        this.controlSetList = function () {
            var l = [];
            for (var i in MARC21.AuthorityControlSet._controlsets) {
                l.push(i);
            }
            return l;
        }
    
        this.findControlSetsForTag = function (tag) {
            var me = this;
            var old_acs = this.controlSetId();
            var acs_list = me.controlSetList().filter(
                function(acs_id) { return (me.controlSet(acs_id).control_map[tag]) }
            );
            this.controlSetId(old_acs);
            return acs_list;
        }
    
        this.findControlSetsForAuthorityTag = function (tag) {
            var me = this;
            var old_acs = this.controlSetId();
    
            var acs_list = me.controlSetList().filter(
                function(acs_id) {
                    var a = me.controlSet(acs_id);
                    for (var btag in a.control_map) {
                        for (var sf in a.control_map[btag]) {
                            if (a.control_map[btag][sf][tag]) return true;
                        }
                    }
                    return false;
                }
            );
            this.controlSetId(old_acs);
            return acs_list;
        }
    
        this.bibToAuthority = function (field) {
            var b_field = this.bibFieldByTag(field.tag);
    
            if (b_field) { // construct an marc authority record
                var af = b_field.authority_field();
    
                var sflist = [];                
                for (var i = 0; i < field.subfields.length; i++) {
                    if (af.sf_list().indexOf(field.subfields[i][0]) > -1) {
                        sflist.push(field.subfields[i]);
                    }
                }
    
                var m = new MARC21.Record ({rtype:'AUT'});
                m.appendFields(
                    new MARC21.Field ({
                        tag : af.tag(),
                        ind1: field.ind1,
                        ind2: field.ind2,
                        subfields: sflist
                    })
                );
    
                return m.toXmlString();
            }
    
            return null;
        }
    
        this.bibToAuthorities = function (field) {
            var auth_list = [];
            var me = this;
    
            var old_acs = this.controlSetId();
            me.controlSetList().forEach(
                function (acs_id) {
                    var acs = me.controlSet(acs_id);
                    var x = me.bibToAuthority(field);
                    if (x) { var foo = {}; foo[acs_id] = x; auth_list.push(foo); }
                }
            );
            this.controlSetId(old_acs);
    
            return auth_list;
        }
    
        // This should not be used in an angular world.  Instead, the call
        // to open-ils.search.authority.simple_heading.from_xml.batch.atomic should
        // be performed by the code that wants to find matching authorities.
        this.findMatchingAuthorities = function (field) {
            return fieldmapper.standardRequest(
                [ 'open-ils.search', 'open-ils.search.authority.simple_heading.from_xml.batch.atomic' ],
                this.bibToAuthorities(field)
            );
        }
    
        if (kwargs.controlSet) {
            this.controlSetId( kwargs.controlSet );
        } else {
            this.controlSetId( this.controlSetList().sort(function(a,b){return (a - b)}) );
        }
    
    }
};

MARC21.Record._recType = {
    BKS : { Type : /[at]{1}/,    BLvl : /[acdm]{1}/ },
    SER : { Type : /[a]{1}/,    BLvl : /[bsi]{1}/ },
    VIS : { Type : /[gkro]{1}/,    BLvl : /[abcdmsi]{1}/ },
    MIX : { Type : /[p]{1}/,    BLvl : /[cdi]{1}/ },
    MAP : { Type : /[ef]{1}/,    BLvl : /[abcdmsi]{1}/ },
    SCO : { Type : /[cd]{1}/,    BLvl : /[abcdmsi]{1}/ },
    REC : { Type : /[ij]{1}/,    BLvl : /[abcdmsi]{1}/ },
    COM : { Type : /[m]{1}/,    BLvl : /[abcdmsi]{1}/ },
    AUT : { Type : /[z]{1}/,    BLvl : /.{1}/ },
    MFHD : { Type : /[uvxy]{1}/,  BLvl : /.{1}/ }
};

MARC21.Record._ff_lengths = {
    '008' : {
        default : 40,
        MFHD    : 32
    }
}

MARC21.Record._ff_pos = {
    AccM : {
        _8 : {
            SCO : {start: 24, len : 6, def : ' ' },
            REC : {start: 24, len : 6, def : ' ' }
        },
        _6 : {
            SCO : {start: 7, len : 6, def : ' ' },
            REC : {start: 7, len : 6, def : ' ' }
        }
    },
    Alph : {
        _8 : {
            SER : {start : 33, len : 1, def : ' ' }
        },
        _6 : {
            SER : {start : 16, len : 1, def : ' ' }
        }
    },
    Audn : {
        _8 : {
            BKS : {start : 22, len : 1, def : ' ' },
            SER : {start : 22, len : 1, def : ' ' },
            VIS : {start : 22, len : 1, def : ' ' },
            SCO : {start : 22, len : 1, def : ' ' },
            REC : {start : 22, len : 1, def : ' ' },
            COM : {start : 22, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 5, len : 1, def : ' ' },
            SER : {start : 5, len : 1, def : ' ' },
            VIS : {start : 5, len : 1, def : ' ' },
            SCO : {start : 5, len : 1, def : ' ' },
            REC : {start : 5, len : 1, def : ' ' },
            COM : {start : 5, len : 1, def : ' ' }
        }
    },
    Biog : {
        _8 : {
            BKS : {start : 34, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 17, len : 1, def : ' ' }
        }
    },
    BLvl : {
        ldr : {
            BKS : {start : 7, len : 1, def : 'm' },
            SER : {start : 7, len : 1, def : 's' },
            VIS : {start : 7, len : 1, def : 'm' },
            MIX : {start : 7, len : 1, def : 'c' },
            MAP : {start : 7, len : 1, def : 'm' },
            SCO : {start : 7, len : 1, def : 'm' },
            REC : {start : 7, len : 1, def : 'm' },
            COM : {start : 7, len : 1, def : 'm' }
        }
    },
    Comp : {
        _8 : {
            SCO : {start : 18, len : 2, def : 'uu'},
            REC : {start : 18, len : 2, def : 'uu'}
        },
        _6 : {
            SCO : {start : 1, len : 2, def : 'uu'},
            REC : {start : 1, len : 2, def : 'uu'}
        },
    },
    Conf : {
        _8 : {
            BKS : {start : 29, len : 1, def : '0' },
            SER : {start : 29, len : 1, def : '0' }
        },
        _6 : {
            BKS : {start : 11, len : 1, def : '0' },
            SER : {start : 11, len : 1, def : '0' }
        }
    },
    Cont : {
        _8 : {
            BKS : {start : 24, len : 4, def : ' ' },
            SER : {start : 25, len : 3, def : ' ' }
        },
        _6 : {
            BKS : {start : 7, len : 4, def : ' ' },
            SER : {start : 8, len : 3, def : ' ' }
        }
    },
    CrTp : {
        _8 : {
            MAP : {start: 25, len : 1, def : 'a' }
        },
        _6 : { 
            MAP : {start : 8, len : 1, def : 'a' }
        }
    },
    Ctrl : {
        ldr : {
            BKS : {start : 8, len : 1, def : ' ' },
            SER : {start : 8, len : 1, def : ' ' },
            VIS : {start : 8, len : 1, def : ' ' },
            MIX : {start : 8, len : 1, def : ' ' },
            MAP : {start : 8, len : 1, def : ' ' },
            SCO : {start : 8, len : 1, def : ' ' },
            REC : {start : 8, len : 1, def : ' ' },
            COM : {start : 8, len : 1, def : ' ' }
        }
    },
    Ctry : {
            _8 : {
                BKS : {start : 15, len : 3, def : ' ' },
                SER : {start : 15, len : 3, def : ' ' },
                VIS : {start : 15, len : 3, def : ' ' },
                MIX : {start : 15, len : 3, def : ' ' },
                MAP : {start : 15, len : 3, def : ' ' },
                SCO : {start : 15, len : 3, def : ' ' },
                REC : {start : 15, len : 3, def : ' ' },
                COM : {start : 15, len : 3, def : ' ' }
            }
        },
    Date1 : {
        _8 : {
            BKS : {start : 7, len : 4, def : ' ' },
            SER : {start : 7, len : 4, def : ' ' },
            VIS : {start : 7, len : 4, def : ' ' },
            MIX : {start : 7, len : 4, def : ' ' },
            MAP : {start : 7, len : 4, def : ' ' },
            SCO : {start : 7, len : 4, def : ' ' },
            REC : {start : 7, len : 4, def : ' ' },
            COM : {start : 7, len : 4, def : ' ' }
        }
    },
    Date2 : {
        _8 : {
            BKS : {start : 11, len : 4, def : ' ' },
            SER : {start : 11, len : 4, def : '9' },
            VIS : {start : 11, len : 4, def : ' ' },
            MIX : {start : 11, len : 4, def : ' ' },
            MAP : {start : 11, len : 4, def : ' ' },
            SCO : {start : 11, len : 4, def : ' ' },
            REC : {start : 11, len : 4, def : ' ' },
            COM : {start : 11, len : 4, def : ' ' }
        }
    },
    Desc : {
        ldr : {
            BKS : {start : 18, len : 1, def : ' ' },
            SER : {start : 18, len : 1, def : ' ' },
            VIS : {start : 18, len : 1, def : ' ' },
            MIX : {start : 18, len : 1, def : ' ' },
            MAP : {start : 18, len : 1, def : ' ' },
            SCO : {start : 18, len : 1, def : ' ' },
            REC : {start : 18, len : 1, def : ' ' },
            COM : {start : 18, len : 1, def : ' ' }
        }
    },
    DtSt : {
        _8 : {
            BKS : {start : 6, len : 1, def : ' ' },
            SER : {start : 6, len : 1, def : 'c' },
            VIS : {start : 6, len : 1, def : ' ' },
            MIX : {start : 6, len : 1, def : ' ' },
            MAP : {start : 6, len : 1, def : ' ' },
            SCO : {start : 6, len : 1, def : ' ' },
            REC : {start : 6, len : 1, def : ' ' },
            COM : {start : 6, len : 1, def : ' ' }
        }
    },
    ELvl : {
        ldr : {
            BKS : {start : 17, len : 1, def : ' ' },
            SER : {start : 17, len : 1, def : ' ' },
            VIS : {start : 17, len : 1, def : ' ' },
            MIX : {start : 17, len : 1, def : ' ' },
            MAP : {start : 17, len : 1, def : ' ' },
            SCO : {start : 17, len : 1, def : ' ' },
            REC : {start : 17, len : 1, def : ' ' },
            COM : {start : 17, len : 1, def : ' ' },
            AUT : {start : 17, len : 1, def : 'n' },
            MFHD : {start : 17, len : 1, def : 'u' }
        }
    },
    EntW : {
        _8 : {
            SER : {start : 24, len : 1, def : ' '}
        },
        _6 : {
            SER : {start : 7, len : 1, def : ' '}
        }
    },
    Fest : {
        _8 : {
            BKS : {start : 30, len : 1, def : '0' }
        },
        _6 : {
            BKS : {start : 13, len : 1, def : '0' }
        }
    },
    File : {
        _8 : {
            COM : {start: 26, len : 1, def : 'u' }
        },
        _6 : {
            COM : {start: 9, len : 1, def : 'u' }
        }
    },
    FMus : {
        _8 : {
            SCO : {start : 20, len : 1, def : 'u'},
            REC : {start : 20, len : 1, def : 'n'}
        },
        _6 : {
            SCO : {start : 3, len : 1, def : 'u'},
            REC : {start : 3, len : 1, def : 'n'}
        },
    },
    Form : {
        _8 : {
            BKS : {start : 23, len : 1, def : ' ' },
            SER : {start : 23, len : 1, def : ' ' },
            VIS : {start : 29, len : 1, def : ' ' },
            MIX : {start : 23, len : 1, def : ' ' },
            MAP : {start : 29, len : 1, def : ' ' },
            SCO : {start : 23, len : 1, def : ' ' },
            REC : {start : 23, len : 1, def : ' ' },
            COM : {start : 23, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 6, len : 1, def : ' ' },
            SER : {start : 6, len : 1, def : ' ' },
            VIS : {start : 12, len : 1, def : ' ' },
            MIX : {start : 6, len : 1, def : ' ' },
            MAP : {start : 12, len : 1, def : ' ' },
            SCO : {start : 6, len : 1, def : ' ' },
            REC : {start : 6, len : 1, def : ' ' },
            COM : {start : 6, len : 1, def : ' ' }
        }
    },
    Freq : {
        _8 : {
            SER : {start : 18, len : 1, def : ' '}
        },
        _6 : {
            SER : {start : 1, len : 1, def : ' '}
        }
    },
    GPub : {
        _8 : {
            BKS : {start : 28, len : 1, def : ' ' },
            SER : {start : 28, len : 1, def : ' ' },
            VIS : {start : 28, len : 1, def : ' ' },
            MAP : {start : 28, len : 1, def : ' ' },
            COM : {start : 28, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 11, len : 1, def : ' ' },
            SER : {start : 11, len : 1, def : ' ' },
            VIS : {start : 11, len : 1, def : ' ' },
            MAP : {start : 11, len : 1, def : ' ' },
            COM : {start : 11, len : 1, def : ' ' }
        }
    },
    Ills : {
        _8 : {
            BKS : {start : 18, len : 4, def : ' ' }
        },
        _6 : {
            BKS : {start : 1, len : 4, def : ' ' }
        }
    },
    Indx : {
        _8 : {
            BKS : {start : 31, len : 1, def : '0' },
            MAP : {start : 31, len : 1, def : '0' }
        },
        _6 : {
            BKS : {start : 14, len : 1, def : '0' },
            MAP : {start : 14, len : 1, def : '0' }
        }
    },
    Item : {
        ldr : {
            MFHD : {start : 18, len : 1, def : 'i' }
        }
    },
    Lang : {
        _8 : {
            BKS : {start : 35, len : 3, def : ' ' },
            SER : {start : 35, len : 3, def : ' ' },
            VIS : {start : 35, len : 3, def : ' ' },
            MIX : {start : 35, len : 3, def : ' ' },
            MAP : {start : 35, len : 3, def : ' ' },
            SCO : {start : 35, len : 3, def : ' ' },
            REC : {start : 35, len : 3, def : ' ' },
            COM : {start : 35, len : 3, def : ' ' }
        }
    },
    LitF : {
        _8 : {
            BKS : {start : 33, len : 1, def : '0' }
        },
        _6 : {
            BKS : {start : 16, len : 1, def : '0' }
        }
    },
    LTxt : {
        _8 : {
            SCO : {start : 30, len : 2, def : 'n'},
            REC : {start : 30, len : 2, def : ' '}
        },
        _6 : {
            SCO : {start : 13, len : 2, def : 'n'},
            REC : {start : 13, len : 2, def : ' '}
        },
    },
    MRec : {
        _8 : {
            BKS : {start : 38, len : 1, def : ' ' },
            SER : {start : 38, len : 1, def : ' ' },
            VIS : {start : 38, len : 1, def : ' ' },
            MIX : {start : 38, len : 1, def : ' ' },
            MAP : {start : 38, len : 1, def : ' ' },
            SCO : {start : 38, len : 1, def : ' ' },
            REC : {start : 38, len : 1, def : ' ' },
            COM : {start : 38, len : 1, def : ' ' }
        }
    },
    Orig : {
        _8 : {
            SER : {start : 22, len : 1, def : ' '}
        },
        _6 : {
            SER : {start: 5, len : 1, def: ' '}
        }
    },
    Part : {
        _8 : {
            SCO : {start : 21, len : 1, def : ' '},
            REC : {start : 21, len : 1, def : 'n'}
        },
        _6 : {
            SCO : {start : 4, len : 1, def : ' '},
            REC : {start : 4, len : 1, def : 'n'}
        },
    },
    Proj : {
        _8 : {
            MAP : {start : 22, len : 2, def : ' ' }
        },
        _6 : {
            MAP: {start : 5, len : 2, def : ' ' }
        }
    },
    RecStat : {
        ldr : {
            BKS : {start : 5, len : 1, def : 'n' },
            SER : {start : 5, len : 1, def : 'n' },
            VIS : {start : 5, len : 1, def : 'n' },
            MIX : {start : 5, len : 1, def : 'n' },
            MAP : {start : 5, len : 1, def : 'n' },
            SCO : {start : 5, len : 1, def : 'n' },
            REC : {start : 5, len : 1, def : 'n' },
            COM : {start : 5, len : 1, def : 'n' },
            MFHD: {start : 5, len : 1, def : 'n' },
            AUT : {start : 5, len : 1, def : 'n' }
        }
    },
    Regl : {
        _8 : {
            SER : {start : 19, len : 1, def : ' '}
        },
        _6 : {
            SER : {start : 2, len : 1, def : ' '}
        }
    },
    Relf : {
        _8 : {
            MAP : {start: 18, len : 4, def : ' '}
        },
        _6 : {
            MAP : {start: 1, len : 4, def : ' '}
        }
    },
    'S/L' : {
        _8 : {
            SER : {start : 34, len : 1, def : '0' }
        },
        _6 : {
            SER : {start : 17, len : 1, def : '0' }
        }
    },
    SpFM : {
        _8 : {
            MAP : {start: 33, len : 2, def : ' ' }
        },
        _6 : {
            MAP : {start: 16, len : 2, def : ' '}
        }
    },
    Srce : {
        _8 : {
            BKS : {start : 39, len : 1, def : 'd' },
            SER : {start : 39, len : 1, def : 'd' },
            VIS : {start : 39, len : 1, def : 'd' },
            SCO : {start : 39, len : 1, def : 'd' },
            REC : {start : 39, len : 1, def : 'd' },
            COM : {start : 39, len : 1, def : 'd' },
            MFHD : {start : 39, len : 1, def : 'd' },
            "AUT" : {"start" : 39, "len" : 1, "def" : 'd' }
        }
    },
    SrTp : {
        _8 : {
            SER : {start : 21, len : 1, def : ' '}
        },
        _6 : {
            SER : {start : 4, len : 1, def : ' '}
        }
    },
    Tech : {
        _8 : {
            VIS : {start : 34, len : 1, def : ' '}
        },
        _6 : {
            VIS : {start : 17, len : 1, def : ' '}
        }
    },
    Time : {
        _8 : {
            VIS : {start : 18, len : 3, def : ' '}
        },
        _6 : {
            VIS : {start : 1, len : 3, def : ' '}
        }
    },
    TMat : {
        _8 : {
            VIS : {start : 33, len : 1, def : ' ' }
        },
        _6 : {
            VIS : {start : 16, len : 1, def : ' ' }
        }
    },
    TrAr : {
        _8 : {
            SCO : {start : 33, len : 1, def : ' ' },
            REC : {start : 33, len : 1, def : 'n' }
        },
        _6 : {
            SCO : {start : 16, len : 1, def : ' ' },
            REC : {start : 16, len : 1, def : 'n' }
        }
    },
    Type : {
        ldr : {
            BKS : {start : 6, len : 1, def : 'a' },
            SER : {start : 6, len : 1, def : 'a' },
            VIS : {start : 6, len : 1, def : 'g' },
            MIX : {start : 6, len : 1, def : 'p' },
            MAP : {start : 6, len : 1, def : 'e' },
            SCO : {start : 6, len : 1, def : 'c' },
            REC : {start : 6, len : 1, def : 'i' },
            COM : {start : 6, len : 1, def : 'm' },
            AUT : {start : 6, len : 1, def : 'z' },
            MFHD : {start : 6, len : 1, def : 'y' }
        }
    },
    "GeoDiv" : {
         "_8" : {
             "AUT" : {"start" : 6, "len" : 1, "def" : ' ' }
         }
     },
     "Roman" : {
         "_8" : {
             "AUT" : {"start" : 7, "len" : 1, "def" : ' ' }
         }
     },
     "CatLang" : {
         "_8" : {
             "AUT" : {"start" : 8, "len" : 1, "def" : ' ' }
         }
     },
     "Kind" : {
         "_8" : {
             "AUT" : {"start" : 9, "len" : 1, "def" : ' ' }
         }
     },
     "Rules" : {
         "_8" : {
             "AUT" : {"start" : 10, "len" : 1, "def" : ' ' }
         }
     },
     "Subj" : {
         "_8" : {
             "AUT" : {"start" : 11, "len" : 1, "def" : ' ' }
         }
     },
     "Series" : {
         "_8" : {
             "AUT" : {"start" : 12, "len" : 1, "def" : ' ' }
         }
     },
     "SerNum" : {
         "_8" : {
             "AUT" : {"start" : 13, "len" : 1, "def" : ' ' }
         }
     },
     "NameUse" : {
         "_8" : {
             "AUT" : {"start" : 14, "len" : 1, "def" : ' ' }
         }
     },
     "SubjUse" : {
         "_8" : {
             "AUT" : {"start" : 15, "len" : 1, "def" : ' ' }
         }
     },
     "SerUse" : {
         "_8" : {
             "AUT" : {"start" : 16, "len" : 1, "def" : ' ' }
         }
     },
     "TypeSubd" : {
         "_8" : {
             "AUT" : {"start" : 17, "len" : 1, "def" : ' ' }
         }
     },
     "GovtAgn" : {
         "_8" : {
             "AUT" : {"start" : 28, "len" : 1, "def" : ' ' }
         }
     },
     "RefStatus" : {
         "_8" : {
             "AUT" : {"start" : 29, "len" : 1, "def" : ' ' }
         }
     },
     "UpdStatus" : {
         "_8" : {
             "AUT" : {"start" : 31, "len" : 1, "def" : ' ' }
         }
     },
     "Name" : {
         "_8" : {
             "AUT" : {"start" : 32, "len" : 1, "def" : ' ' }
         }
     },
     "Status" : {
         "_8" : {
             "AUT" : {"start" : 33, "len" : 1, "def" : ' ' }
         }
     },
     "ModRec" : {
         "_8" : {
             "AUT" : {"start" : 38, "len" : 1, "def" : ' ' }
         }
     },
     "Source" : {
         "_8" : {
             "AUT" : {"start" : 39, "len" : 1, "def" : ' ' }
         }
     }
};

MARC21.Record._physical_characteristics = {
    c : {
        label     : "Electronic Resource",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {    a : "Tape Cartridge",
                        b : "Chip cartridge",
                        c : "Computer optical disk cartridge",
                        f : "Tape cassette",
                        h : "Tape reel",
                        j : "Magnetic disk",
                        m : "Magneto-optical disk",
                        o : "Optical disk",
                        r : "Remote",
                        u : "Unspecified",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 1,
                label : "Color",
                values: {    a : "One color",
                        b : "Black-and-white",
                        c : "Multicolored",
                        g : "Gray scale",
                        m : "Mixed",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Dimensions",
                values: {    a : "3 1/2 in.",
                        e : "12 in.",
                        g : "4 3/4 in. or 12 cm.",
                        i : "1 1/8 x 2 3/8 in.",
                        j : "3 7/8 x 2 1/2 in.",
                        n : "Not applicable",
                        o : "5 1/4 in.",
                        u : "Unknown",
                        v : "8 in.",
                        z : "Other"
                }
            },
            f : {    start : 5,
                len   : 1,
                label : "Sound",
                values: {    ' ' : "No sound (Silent)",
                        a   : "Sound",
                        u   : "Unknown"
                }
            },
            g : {    start : 6,
                len   : 3,
                label : "Image bit depth",
                values: {    mmm   : "Multiple",
                        nnn   : "Not applicable",
                        '---' : "Unknown"
                }
            },
            h : {    start : 9,
                len   : 1,
                label : "File formats",
                values: {    a : "One file format",
                        m : "Multiple file formats",
                        u : "Unknown"
                }
            },
            i : {    start : 10,
                len   : 1,
                label : "Quality assurance target(s)",
                values: {    a : "Absent",
                        n : "Not applicable",
                        p : "Present",
                        u : "Unknown"
                }
            },
            j : {    start : 11,
                len   : 1,
                label : "Antecedent/Source",
                values: {    a : "File reproduced from original",
                        b : "File reproduced from microform",
                        c : "File reproduced from electronic resource",
                        d : "File reproduced from an intermediate (not microform)",
                        m : "Mixed",
                        n : "Not applicable",
                        u : "Unknown"
                }
            },
            k : {    start : 12,
                len   : 1,
                label : "Level of compression",
                values: {    a : "Uncompressed",
                        b : "Lossless",
                        d : "Lossy",
                        m : "Mixed",
                        u : "Unknown"
                }
            },
            l : {    start : 13,
                len   : 1,
                label : "Reformatting quality",
                values: {    a : "Access",
                        n : "Not applicable",
                        p : "Preservation",
                        r : "Replacement",
                        u : "Unknown"
                }
            }
        }
    },
    d : {
        label     : "Globe",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {    a : "Celestial globe",
                        b : "Planetary or lunar globe",
                        c : "Terrestrial globe",
                        e : "Earth moon globe",
                        u : "Unspecified",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 1,
                label : "Color",
                values: {    a : "One color",
                        c : "Multicolored"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Physical medium",
                values: {    a : "Paper",
                        b : "Wood",
                        c : "Stone",
                        d : "Metal",
                        e : "Synthetics",
                        f : "Skins",
                        g : "Textile",
                        p : "Plaster",
                        u : "Unknown",
                        z : "Other"
                }
            },
            f : {    start : 5,
                len   : 1,
                label : "Type of reproduction",
                values: {    f : "Facsimile",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            }
        }
    },
    a : {
        label     : "Map",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {    d : "Atlas",
                        g : "Diagram",
                        j : "Map",
                        k : "Profile",
                        q : "Model",
                        r : "Remote-sensing image",
                        s : "Section",
                        u : "Unspecified",
                        y : "View",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 1,
                label : "Color",
                values: {    a : "One color",
                        c : "Multicolored"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Physical medium",
                values: {    a : "Paper",
                        b : "Wood",
                        c : "Stone",
                        d : "Metal",
                        e : "Synthetics",
                        f : "Skins",
                        g : "Textile",
                        p : "Plaster",
                        q : "Flexible base photographic medium, positive",
                        r : "Flexible base photographic medium, negative",
                        s : "Non-flexible base photographic medium, positive",
                        t : "Non-flexible base photographic medium, negative",
                        u : "Unknown",
                        y : "Other photographic medium",
                        z : "Other"
                }
            },
            f : {    start : 5,
                len   : 1,
                label : "Type of reproduction",
                values: {    f : "Facsimile",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            g : {    start : 6,
                len   : 1,
                label : "Production/reproduction details",
                values: {    a : "Photocopy, blueline print",
                        b : "Photocopy",
                        c : "Pre-production",
                        d : "Film",
                        u : "Unknown",
                        z : "Other"
                }
            },
            h : {    start : 7,
                len   : 1,
                label : "Positive/negative",
                values: {    a : "Positive",
                        b : "Negative",
                        m : "Mixed",
                        n : "Not applicable"
                }
            }
        }
    },
    h : {
        label     : "Microform",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {    a : "Aperture card",
                        b : "Microfilm cartridge",
                        c : "Microfilm cassette",
                        d : "Microfilm reel",
                        e : "Microfiche",
                        f : "Microfiche cassette",
                        g : "Microopaque",
                        u : "Unspecified",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 1,
                label : "Positive/negative",
                values: {    a : "Positive",
                        b : "Negative",
                        m : "Mixed",
                        u : "Unknown"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Dimensions",
                values: {    a : "8 mm.",
                        e : "16 mm.",
                        f : "35 mm.",
                        g : "70mm.",
                        h : "105 mm.",
                        l : "3 x 5 in. (8 x 13 cm.)",
                        m : "4 x 6 in. (11 x 15 cm.)",
                        o : "6 x 9 in. (16 x 23 cm.)",
                        p : "3 1/4 x 7 3/8 in. (9 x 19 cm.)",
                        u : "Unknown",
                        z : "Other"
                }
            },
            f : {    start : 5,
                len   : 4,
                label : "Reduction ratio range/Reduction ratio",
                values: {    a : "Low (1-16x)",
                        b : "Normal (16-30x)",
                        c : "High (31-60x)",
                        d : "Very high (61-90x)",
                        e : "Ultra (90x-)",
                        u : "Unknown",
                        v : "Reduction ratio varies"
                }
            },
            g : {    start : 9,
                len   : 1,
                label : "Color",
                values: {    b : "Black-and-white",
                        c : "Multicolored",
                        m : "Mixed",
                        u : "Unknown",
                        z : "Other"
                }
            },
            h : {    start : 10,
                len   : 1,
                label : "Emulsion on film",
                values: {    a : "Silver halide",
                        b : "Diazo",
                        c : "Vesicular",
                        m : "Mixed",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            i : {    start : 11,
                len   : 1,
                label : "Quality assurance target(s)",
                values: {    a : "1st gen. master",
                        b : "Printing master",
                        c : "Service copy",
                        m : "Mixed generation",
                        u : "Unknown"
                }
            },
            j : {    start : 12,
                len   : 1,
                label : "Base of film",
                values: {    a : "Safety base, undetermined",
                        c : "Safety base, acetate undetermined",
                        d : "Safety base, diacetate",
                        l : "Nitrate base",
                        m : "Mixed base",
                        n : "Not applicable",
                        p : "Safety base, polyester",
                        r : "Safety base, mixed",
                        t : "Safety base, triacetate",
                        u : "Unknown",
                        z : "Other"
                }
            }
        }
    },
    m : {
        label     : "Motion Picture",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {    a : "Film cartridge",
                        f : "Film cassette",
                        r : "Film reel",
                        u : "Unspecified",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 1,
                label : "Color",
                values: {    b : "Black-and-white",
                        c : "Multicolored",
                        h : "Hand-colored",
                        m : "Mixed",
                        u : "Unknown",
                        z : "Other"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Motion picture presentation format",
                values: {    a : "Standard sound aperture, reduced frame",
                        b : "Nonanamorphic (wide-screen)",
                        c : "3D",
                        d : "Anamorphic (wide-screen)",
                        e : "Other-wide screen format",
                        f : "Standard. silent aperture, full frame",
                        u : "Unknown",
                        z : "Other"
                }
            },
            f : {    start : 5,
                len   : 1,
                label : "Sound on medium or separate",
                values: {    a : "Sound on medium",
                        b : "Sound separate from medium",
                        u : "Unknown"
                }
            },
            g : {    start : 6,
                len   : 1,
                label : "Medium for sound",
                values: {    a : "Optical sound track on motion picture film",
                        b : "Magnetic sound track on motion picture film",
                        c : "Magnetic audio tape in cartridge",
                        d : "Sound disc",
                        e : "Magnetic audio tape on reel",
                        f : "Magnetic audio tape in cassette",
                        g : "Optical and magnetic sound track on film",
                        h : "Videotape",
                        i : "Videodisc",
                        u : "Unknown",
                        z : "Other"
                }
            },
            h : {    start : 7,
                len   : 1,
                label : "Dimensions",
                values: {    a : "Standard 8 mm.",
                        b : "Super 8 mm./single 8 mm.",
                        c : "9.5 mm.",
                        d : "16 mm.",
                        e : "28 mm.",
                        f : "35 mm.",
                        g : "70 mm.",
                        u : "Unknown",
                        z : "Other"
                }
            },
            i : {    start : 8,
                len   : 1,
                label : "Configuration of playback channels",
                values: {    k : "Mixed",
                        m : "Monaural",
                        n : "Not applicable",
                        q : "Multichannel, surround or quadraphonic",
                        s : "Stereophonic",
                        u : "Unknown",
                        z : "Other"
                }
            },
            j : {    start : 9,
                len   : 1,
                label : "Production elements",
                values: {    a : "Work print",
                        b : "Trims",
                        c : "Outtakes",
                        d : "Rushes",
                        e : "Mixing tracks",
                        f : "Title bands/inter-title rolls",
                        g : "Production rolls",
                        n : "Not applicable",
                        z : "Other"
                }
            }
        }
    },
    k : {
        label     : "Non-projected Graphic",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {    c : "Collage",
                        d : "Drawing",
                        e : "Painting",
                        f : "Photo-mechanical print",
                        g : "Photonegative",
                        h : "Photoprint",
                        i : "Picture",
                        j : "Print",
                        l : "Technical drawing",
                        n : "Chart",
                        o : "Flash/activity card",
                        u : "Unspecified",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 1,
                label : "Color",
                values: {    a : "One color",
                        b : "Black-and-white",
                        c : "Multicolored",
                        h : "Hand-colored",
                        m : "Mixed",
                        u : "Unknown",
                        z : "Other"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Primary support material",
                values: {    a : "Canvas",
                        b : "Bristol board",
                        c : "Cardboard/illustration board",
                        d : "Glass",
                        e : "Synthetics",
                        f : "Skins",
                        g : "Textile",
                        h : "Metal",
                        m : "Mixed collection",
                        o : "Paper",
                        p : "Plaster",
                        q : "Hardboard",
                        r : "Porcelain",
                        s : "Stone",
                        t : "Wood",
                        u : "Unknown",
                        z : "Other"
                }
            },
            f : {    start : 5,
                len   : 1,
                label : "Secondary support material",
                values: {    a : "Canvas",
                        b : "Bristol board",
                        c : "Cardboard/illustration board",
                        d : "Glass",
                        e : "Synthetics",
                        f : "Skins",
                        g : "Textile",
                        h : "Metal",
                        m : "Mixed collection",
                        o : "Paper",
                        p : "Plaster",
                        q : "Hardboard",
                        r : "Porcelain",
                        s : "Stone",
                        t : "Wood",
                        u : "Unknown",
                        z : "Other"
                }
            }
        }
    },
    g : {
        label     : "Projected Graphic",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {    c : "Film cartridge",
                        d : "Filmstrip",
                        f : "Film filmstrip type",
                        o : "Filmstrip roll",
                        s : "Slide",
                        t : "Transparency",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 1,
                label : "Color",
                values: {    b : "Black-and-white",
                        c : "Multicolored",
                        h : "Hand-colored",
                        m : "Mixed",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Base of emulsion",
                values: {    d : "Glass",
                        e : "Synthetics",
                        j : "Safety film",
                        k : "Film base, other than safety film",
                        m : "Mixed collection",
                        o : "Paper",
                        u : "Unknown",
                        z : "Other"
                }
            },
            f : {    start : 5,
                len   : 1,
                label : "Sound on medium or separate",
                values: {    a : "Sound on medium",
                        b : "Sound separate from medium",
                        u : "Unknown"
                }
            },
            g : {    start : 6,
                len   : 1,
                label : "Medium for sound",
                values: {    a : "Optical sound track on motion picture film",
                        b : "Magnetic sound track on motion picture film",
                        c : "Magnetic audio tape in cartridge",
                        d : "Sound disc",
                        e : "Magnetic audio tape on reel",
                        f : "Magnetic audio tape in cassette",
                        g : "Optical and magnetic sound track on film",
                        h : "Videotape",
                        i : "Videodisc",
                        u : "Unknown",
                        z : "Other"
                }
            },
            h : {    start : 7,
                len   : 1,
                label : "Dimensions",
                values: {    a : "Standard 8 mm.",
                        b : "Super 8 mm./single 8 mm.",
                        c : "9.5 mm.",
                        d : "16 mm.",
                        e : "28 mm.",
                        f : "35 mm.",
                        g : "70 mm.",
                        j : "2 x 2 in. (5 x 5 cm.)",
                        k : "2 1/4 x 2 1/4 in. (6 x 6 cm.)",
                        s : "4 x 5 in. (10 x 13 cm.)",
                        t : "5 x 7 in. (13 x 18 cm.)",
                        v : "8 x 10 in. (21 x 26 cm.)",
                        w : "9 x 9 in. (23 x 23 cm.)",
                        x : "10 x 10 in. (26 x 26 cm.)",
                        y : "7 x 7 in. (18 x 18 cm.)",
                        u : "Unknown",
                        z : "Other"
                }
            },
            i : {    start : 8,
                len   : 1,
                label : "Secondary support material",
                values: {    c : "Cardboard",
                        d : "Glass",
                        e : "Synthetics",
                        h : "metal",
                        j : "Metal and glass",
                        k : "Synthetics and glass",
                        m : "Mixed collection",
                        u : "Unknown",
                        z : "Other"
                }
            }
        }
    },
    r : {
        label     : "Remote-sensing Image",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: { u : "Unspecified" }
            },
            d : {    start : 3,
                len   : 1,
                label : "Altitude of sensor",
                values: {    a : "Surface",
                        b : "Airborne",
                        c : "Spaceborne",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Attitude of sensor",
                values: {    a : "Low oblique",
                        b : "High oblique",
                        c : "Vertical",
                        n : "Not applicable",
                        u : "Unknown"
                }
            },
            f : {    start : 5,
                len   : 1,
                label : "Cloud cover",
                values: {    0 : "0-09%",
                        1 : "10-19%",
                        2 : "20-29%",
                        3 : "30-39%",
                        4 : "40-49%",
                        5 : "50-59%",
                        6 : "60-69%",
                        7 : "70-79%",
                        8 : "80-89%",
                        9 : "90-100%",
                        n : "Not applicable",
                        u : "Unknown"
                }
            },
            g : {    start : 6,
                len   : 1,
                label : "Platform construction type",
                values: {    a : "Balloon",
                        b : "Aircraft-low altitude",
                        c : "Aircraft-medium altitude",
                        d : "Aircraft-high altitude",
                        e : "Manned spacecraft",
                        f : "Unmanned spacecraft",
                        g : "Land-based remote-sensing device",
                        h : "Water surface-based remote-sensing device",
                        i : "Submersible remote-sensing device",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            h : {    start : 7,
                len   : 1,
                label : "Platform use category",
                values: {    a : "Meteorological",
                        b : "Surface observing",
                        c : "Space observing",
                        m : "Mixed uses",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            i : {    start : 8,
                len   : 1,
                label : "Sensor type",
                values: {    a : "Active",
                        b : "Passive",
                        u : "Unknown",
                        z : "Other"
                }
            },
            j : {    start : 9,
                len   : 2,
                label : "Data type",
                values: {    nn : "Not applicable",
                        uu : "Unknown",
                        zz : "Other",
                        aa : "Visible light",
                        da : "Near infrared",
                        db : "Middle infrared",
                        dc : "Far infrared",
                        dd : "Thermal infrared",
                        de : "Shortwave infrared (SWIR)",
                        df : "Reflective infrared",
                        dv : "Combinations",
                        dz : "Other infrared data",
                        ga : "Sidelooking airborne radar (SLAR)",
                        gb : "Synthetic aperture radar (SAR-single frequency)",
                        gc : "SAR-multi-frequency (multichannel)",
                        gd : "SAR-like polarization",
                        ge : "SAR-cross polarization",
                        gf : "Infometric SAR",
                        gg : "Polarmetric SAR",
                        gu : "Passive microwave mapping",
                        gz : "Other microwave data",
                        ja : "Far ultraviolet",
                        jb : "Middle ultraviolet",
                        jc : "Near ultraviolet",
                        jv : "Ultraviolet combinations",
                        jz : "Other ultraviolet data",
                        ma : "Multi-spectral, multidata",
                        mb : "Multi-temporal",
                        mm : "Combination of various data types",
                        pa : "Sonar-water depth",
                        pb : "Sonar-bottom topography images, sidescan",
                        pc : "Sonar-bottom topography, near-surface",
                        pd : "Sonar-bottom topography, near-bottom",
                        pe : "Seismic surveys",
                        pz : "Other acoustical data",
                        ra : "Gravity anomales (general)",
                        rb : "Free-air",
                        rc : "Bouger",
                        rd : "Isostatic",
                        sa : "Magnetic field",
                        ta : "Radiometric surveys"
                }
            }
        }
    },
    s : {
        label     : "Sound Recording",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {    d : "Sound disc",
                        e : "Cylinder",
                        g : "Sound cartridge",
                        i : "Sound-track film",
                        q : "Roll",
                        s : "Sound cassette",
                        t : "Sound-tape reel",
                        u : "Unspecified",
                        w : "Wire recording",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 1,
                label : "Speed",
                values: {    a : "16 rpm",
                        b : "33 1/3 rpm",
                        c : "45 rpm",
                        d : "78 rpm",
                        e : "8 rpm",
                        f : "1.4 mps",
                        h : "120 rpm",
                        i : "160 rpm",
                        k : "15/16 ips",
                        l : "1 7/8 ips",
                        m : "3 3/4 ips",
                        o : "7 1/2 ips",
                        p : "15 ips",
                        r : "30 ips",
                        u : "Unknown",
                        z : "Other"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Configuration of playback channels",
                values: {    m : "Monaural",
                        q : "Quadraphonic",
                        s : "Stereophonic",
                        u : "Unknown",
                        z : "Other"
                }
            },
            f : {    start : 5,
                len   : 1,
                label : "Groove width or pitch",
                values: {    m : "Microgroove/fine",
                        n : "Not applicable",
                        s : "Coarse/standard",
                        u : "Unknown",
                        z : "Other"
                }
            },
            g : {    start : 6,
                len   : 1,
                label : "Dimensions",
                values: {    a : "3 in.",
                        b : "5 in.",
                        c : "7 in.",
                        d : "10 in.",
                        e : "12 in.",
                        f : "16 in.",
                        g : "4 3/4 in. (12 cm.)",
                        j : "3 7/8 x 2 1/2 in.",
                        o : "5 1/4 x 3 7/8 in.",
                        s : "2 3/4 x 4 in.",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            h : {    start : 7,
                len   : 1,
                label : "Tape width",
                values: {    l : "1/8 in.",
                        m : "1/4in.",
                        n : "Not applicable",
                        o : "1/2 in.",
                        p : "1 in.",
                        u : "Unknown",
                        z : "Other"
                }
            },
            i : {    start : 8,
                len   : 1,
                label : "Tape configuration ",
                values: {    a : "Full (1) track",
                        b : "Half (2) track",
                        c : "Quarter (4) track",
                        d : "8 track",
                        e : "12 track",
                        f : "16 track",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            m : {    start : 12,
                len   : 1,
                label : "Special playback",
                values: {    a : "NAB standard",
                        b : "CCIR standard",
                        c : "Dolby-B encoded, standard Dolby",
                        d : "dbx encoded",
                        e : "Digital recording",
                        f : "Dolby-A encoded",
                        g : "Dolby-C encoded",
                        h : "CX encoded",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            n : {    start : 13,
                len   : 1,
                label : "Capture and storage",
                values: {    a : "Acoustical capture, direct storage",
                        b : "Direct storage, not acoustical",
                        d : "Digital storage",
                        e : "Analog electrical storage",
                        u : "Unknown",
                        z : "Other"
                }
            }
        }
    },
    f : {
        label     : "Tactile Material",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {    a : "Moon",
                        b : "Braille",
                        c : "Combination",
                        d : "Tactile, with no writing system",
                        u : "Unspecified",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 2,
                label : "Class of braille writing",
                values: {    a : "Literary braille",
                        b : "Format code braille",
                        c : "Mathematics and scientific braille",
                        d : "Computer braille",
                        e : "Music braille",
                        m : "Multiple braille types",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Level of contraction",
                values: {    a : "Uncontracted",
                        b : "Contracted",
                        m : "Combination",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            f : {    start : 6,
                len   : 3,
                label : "Braille music format",
                values: {    a : "Bar over bar",
                        b : "Bar by bar",
                        c : "Line over line",
                        d : "Paragraph",
                        e : "Single line",
                        f : "Section by section",
                        g : "Line by line",
                        h : "Open score",
                        i : "Spanner short form scoring",
                        j : "Short form scoring",
                        k : "Outline",
                        l : "Vertical score",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            g : {    start : 9,
                len   : 1,
                label : "Special physical characteristics",
                values: {    a : "Print/braille",
                        b : "Jumbo or enlarged braille",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            }
        }
    },
    v : {
        label     : "Videorecording",
        subfields : {
            b : {    start : 1,
                len   : 1,
                label : "SMD",
                values: {     c : "Videocartridge",
                        d : "Videodisc",
                        f : "Videocassette",
                        r : "Videoreel",
                        u : "Unspecified",
                        z : "Other"
                }
            },
            d : {    start : 3,
                len   : 1,
                label : "Color",
                values: {    b : "Black-and-white",
                        c : "Multicolored",
                        m : "Mixed",
                        n : "Not applicable",
                        u : "Unknown",
                        z : "Other"
                }
            },
            e : {    start : 4,
                len   : 1,
                label : "Videorecording format",
                values: {    a : "Beta",
                        b : "VHS",
                        c : "U-matic",
                        d : "EIAJ",
                        e : "Type C",
                        f : "Quadruplex",
                        g : "Laserdisc",
                        h : "CED",
                        i : "Betacam",
                        j : "Betacam SP",
                        k : "Super-VHS",
                        m : "M-II",
                        o : "D-2",
                        p : "8 mm.",
                        q : "Hi-8 mm.",
                        u : "Unknown",
                        v : "DVD",
                        z : "Other"
                }
            },
            f : {    start : 5,
                len   : 1,
                label : "Sound on medium or separate",
                values: {    a : "Sound on medium",
                        b : "Sound separate from medium",
                        u : "Unknown"
                }
            },
            g : {    start : 6,
                len   : 1,
                label : "Medium for sound",
                values: {    a : "Optical sound track on motion picture film",
                        b : "Magnetic sound track on motion picture film",
                        c : "Magnetic audio tape in cartridge",
                        d : "Sound disc",
                        e : "Magnetic audio tape on reel",
                        f : "Magnetic audio tape in cassette",
                        g : "Optical and magnetic sound track on motion picture film",
                        h : "Videotape",
                        i : "Videodisc",
                        u : "Unknown",
                        z : "Other"
                }
            },
            h : {    start : 7,
                len   : 1,
                label : "Dimensions",
                values: {    a : "8 mm.",
                        m : "1/4 in.",
                        o : "1/2 in.",
                        p : "1 in.",
                        q : "2 in.",
                        r : "3/4 in.",
                        u : "Unknown",
                        z : "Other"
                }
            },
            i : {    start : 8,
                len   : 1,
                label : "Configuration of playback channel",
                values: {    k : "Mixed",
                        m : "Monaural",
                        n : "Not applicable",
                        q : "Multichannel, surround or quadraphonic",
                        s : "Stereophonic",
                        u : "Unknown",
                        z : "Other"
                }
            }
        }
    }
};

MARC21.AuthorityControlSet._remote_loaded = false;
MARC21.AuthorityControlSet._remote_parsed = false;

MARC21.AuthorityControlSet._controlsets = {
    // static sorta-LoC setup ... to be overwritten with server data 
    '-1' : {
        id : -1,
        name : 'Static LoC legacy mapping',
        description : 'Legacy mapping provided as a default',
        control_map : {
            100 : {
                'a' : { 100 : 'a' },
                'd' : { 100 : 'd' },
                'e' : { 100 : 'e' },
                'q' : { 100 : 'q' }
            },
            110 : {
                'a' : { 110 : 'a' },
                'd' : { 110 : 'd' }
            },
            111 : {
                'a' : { 111 : 'a' },
                'd' : { 111 : 'd' }
            },
            130 : {
                'a' : { 130 : 'a' },
                'd' : { 130 : 'd' }
            },
            240 : {
                'a' : { 130 : 'a' },
                'd' : { 130 : 'd' }
            },
            400 : {
                'a' : { 100 : 'a' },
                'd' : { 100 : 'd' }
            },
            410 : {
                'a' : { 110 : 'a' },
                'd' : { 110 : 'd' }
            },
            411 : {
                'a' : { 111 : 'a' },
                'd' : { 111 : 'd' }
            },
            440 : {
                'a' : { 130 : 'a' },
                'n' : { 130 : 'n' },
                'p' : { 130 : 'p' }
            },
            700 : {
                'a' : { 100 : 'a' },
                'd' : { 100 : 'd' },
                'q' : { 100 : 'q' },
                't' : { 100 : 't' }
            },
            710 : {
                'a' : { 110 : 'a' },
                'd' : { 110 : 'd' }
            },
            711 : {
                'a' : { 111 : 'a' },
                'c' : { 111 : 'c' },
                'd' : { 111 : 'd' }
            },
            730 : {
                'a' : { 130 : 'a' },
                'd' : { 130 : 'd' }
            },
            800 : {
                'a' : { 100 : 'a' },
                'd' : { 100 : 'd' }
            },
            810 : {
                'a' : { 110 : 'a' },
                'd' : { 110 : 'd' }
            },
            811 : {
                'a' : { 111 : 'a' },
                'd' : { 111 : 'd' }
            },
            830 : {
                'a' : { 130 : 'a' },
                'd' : { 130 : 'd' }
            },
            600 : {
                'a' : { 100 : 'a' },
                'd' : { 100 : 'd' },
                'q' : { 100 : 'q' },
                't' : { 100 : 't' },
                'v' : { 180 : 'v',
                    100 : 'v',
                    181 : 'v',
                    182 : 'v',
                    185 : 'v'
                },
                'x' : { 180 : 'x',
                    100 : 'x',
                    181 : 'x',
                    182 : 'x',
                    185 : 'x'
                },
                'y' : { 180 : 'y',
                    100 : 'y',
                    181 : 'y',
                    182 : 'y',
                    185 : 'y'
                },
                'z' : { 180 : 'z',
                    100 : 'z',
                    181 : 'z',
                    182 : 'z',
                    185 : 'z'
                }
            },
            610 : {
                'a' : { 110 : 'a' },
                'd' : { 110 : 'd' },
                't' : { 110 : 't' },
                'v' : { 180 : 'v',
                    110 : 'v',
                    181 : 'v',
                    182 : 'v',
                    185 : 'v'
                },
                'x' : { 180 : 'x',
                    110 : 'x',
                    181 : 'x',
                    182 : 'x',
                    185 : 'x'
                },
                'y' : { 180 : 'y',
                    110 : 'y',
                    181 : 'y',
                    182 : 'y',
                    185 : 'y'
                },
                'z' : { 180 : 'z',
                    110 : 'z',
                    181 : 'z',
                    182 : 'z',
                    185 : 'z'
                }
            },
            611 : {
                'a' : { 111 : 'a' },
                'd' : { 111 : 'd' },
                't' : { 111 : 't' },
                'v' : { 180 : 'v',
                    111 : 'v',
                    181 : 'v',
                    182 : 'v',
                    185 : 'v'
                },
                'x' : { 180 : 'x',
                    111 : 'x',
                    181 : 'x',
                    182 : 'x',
                    185 : 'x'
                },
                'y' : { 180 : 'y',
                    111 : 'y',
                    181 : 'y',
                    182 : 'y',
                    185 : 'y'
                },
                'z' : { 180 : 'z',
                    111 : 'z',
                    181 : 'z',
                    182 : 'z',
                    185 : 'z'
                }
            },
            630 : {
                'a' : { 130 : 'a' },
                'd' : { 130 : 'd' }
            },
            648 : {
                'a' : { 148 : 'a' },
                'v' : { 148 : 'v' },
                'x' : { 148 : 'x' },
                'y' : { 148 : 'y' },
                'z' : { 148 : 'z' }
            },
            650 : {
                'a' : { 150 : 'a' },
                'b' : { 150 : 'b' },
                'v' : { 180 : 'v',
                    150 : 'v',
                    181 : 'v',
                    182 : 'v',
                    185 : 'v'
                },
                'x' : { 180 : 'x',
                    150 : 'x',
                    181 : 'x',
                    182 : 'x',
                    185 : 'x'
                },
                'y' : { 180 : 'y',
                    150 : 'y',
                    181 : 'y',
                    182 : 'y',
                    185 : 'y'
                },
                'z' : { 180 : 'z',
                    150 : 'z',
                    181 : 'z',
                    182 : 'z',
                    185 : 'z'
                }
            },
            651 : {
                'a' : { 151 : 'a' },
                'v' : { 180 : 'v',
                    151 : 'v',
                    181 : 'v',
                    182 : 'v',
                    185 : 'v'
                },
                'x' : { 180 : 'x',
                    151 : 'x',
                    181 : 'x',
                    182 : 'x',
                    185 : 'x'
                },
                'y' : { 180 : 'y',
                    151 : 'y',
                    181 : 'y',
                    182 : 'y',
                    185 : 'y'
                },
                'z' : { 180 : 'z',
                    151 : 'z',
                    181 : 'z',
                    182 : 'z',
                    185 : 'z'
                }
            },
            655 : {
                'a' : { 155 : 'a' },
                'v' : { 180 : 'v',
                    155 : 'v',
                    181 : 'v',
                    182 : 'v',
                    185 : 'v'
                },
                'x' : { 180 : 'x',
                    155 : 'x',
                    181 : 'x',
                    182 : 'x',
                    185 : 'x'
                },
                'y' : { 180 : 'y',
                    155 : 'y',
                    181 : 'y',
                    182 : 'y',
                    185 : 'y'
                },
                'z' : { 180 : 'z',
                    155 : 'z',
                    181 : 'z',
                    182 : 'z',
                    185 : 'z'
                }
            }
        }
    }
};

