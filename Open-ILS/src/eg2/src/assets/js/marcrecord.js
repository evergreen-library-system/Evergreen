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

/*
 * Copy of file from Open-ILS/web/js/ui/default/staff/marcrecord.js
 *
 * This copy of the the MARC21 library heavily modified by
 * Bill Erickson <berickxx@gmail.com> 2019 circa Evergreen 3.3.
 *
 * 1. All jquery dependencies have been replaced with Vanilla JS.
 * 2. Many features from the original have been removed (for now,
 *    anyway) since they were not needed at the time and would have
 *    required additional jquery porting work.
 * 
 * Code is otherwise unchanged.
 */

/**
 * As an external dependency, this JS is loaded on every Angular page.
 * We could migrate it into the Angular app as Typescript so it's only
 * loaded when needed (e.g. in the marc editor component).
 */

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

        this.fromXmlString = function (mxml) {
            var xmlDoc = new DOMParser().parseFromString(mxml, "text/xml");
            this.fromXmlDocument(xmlDoc.getElementsByTagName('record')[0]);
        }

        this.fromXmlDocument = function (mxml) {
            var me = this;
            var ldr =  mxml.getElementsByTagName('leader')[0];
            me.leader = (ldr ? ldr.textContent : '') || '00000cam a2200205Ka 4500';

            var cfNodes = mxml.getElementsByTagName('controlfield');
            for (var idx = 0; idx < cfNodes.length; idx++) {
                var cf = cfNodes[idx];
                me.fields.push(
                    new MARC21.Field({
                          record : me,
                          tag    : cf.getAttribute('tag'),
                          data   : cf.textContent
                    })
                );
            }

            var dfNodes = mxml.getElementsByTagName('datafield');
            for (var idx = 0; idx < dfNodes.length; idx++) {
                var df = dfNodes[idx];

                var sfNodes = df.getElementsByTagName('subfield');
                var subfields = [];
                for (var idx2 = 0; idx2 < sfNodes.length; idx2++) {
                    var sf = sfNodes[idx2];
                    subfields.push(
                        [sf.getAttribute('code'), sf.textContent, idx2]);
                }

                me.fields.push(
                    new MARC21.Field({
                        record    : me,
                        tag       : df.getAttribute('tag'),
                        ind1      : df.getAttribute('ind1'),
                        ind2      : df.getAttribute('ind2'),
                        subfields : subfields
                    })
                );
            }

            for (var j = 0; j < this.fields.length; j++) {
                this.fields[j].position = j;
            }

            me.ready = true;
        }

        this.toXmlDocument = function () {

            var doc = new DOMParser().parseFromString(
                '<record xmlns="http://www.loc.gov/MARC21/slim"/>', 'text/xml');

            var rec_node = doc.getElementsByTagName('record')[0];

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
        
        this.isFixedFieldMultivalue = function (field) {
            if (!MARC21.Record._ff_pos[field]) return false;
        
            var _l = this.leader;
            var _8 = this.field('008').data;
            var _6 = this.field('006').data;
            /*
            console.debug('008', MARC21.Record._ff_pos[field]._8);
            console.debug('006', MARC21.Record._ff_pos[field]._6);
            console.debug('001', MARC21.Record._ff_pos[field]._l);
            /***/
        
            var rtype = this.recordType();

            if (_8 && MARC21.Record._ff_pos[field]._8 && MARC21.Record._ff_pos[field]._8[rtype])
                return !!MARC21.Record._ff_pos[field]._8[rtype].multivalue || false;
            
            if (_6 && MARC21.Record._ff_pos[field]._6 && MARC21.Record._ff_pos[field]._6[rtype])
                return !!MARC21.Record._ff_pos[field]._6[rtype].multivalue || false;

            if (_l && MARC21.Record._ff_pos[field]._l && MARC21.Record._ff_pos[field]._l[rtype])
                return !!MARC21.Record._ff_pos[field]._l[rtype].multivalue || false;

            return false;
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
            //this.fromXmlURL(kwargs.url);
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
            SCO : {start: 24, len : 6, def : ' ', multivalue : true },
            REC : {start: 24, len : 6, def : ' ', multivalue : true  }
        },
        _6 : {
            SCO : {start: 7, len : 6, def : ' ', multivalue : true  },
            REC : {start: 7, len : 6, def : ' ', multivalue : true  }
        }
    },
    // break out all six AccM characters individually:
    AccM1 : {
        _8 : {
            SCO : {start: 24, len : 1, def : ' ' },
            REC : {start: 24, len : 1, def : ' ' }
        },
        _6 : {
            SCO : {start: 7, len : 1, def : ' ' },
            REC : {start: 7, len : 1, def : ' ' }
        }
    },
    AccM2 : {
        _8 : {
            SCO : {start: 25, len : 1, def : ' ' },
            REC : {start: 25, len : 1, def : ' ' }
        },
        _6 : {
            SCO : {start: 8, len : 1, def : ' ' },
            REC : {start: 8, len : 1, def : ' ' }
        }
    },
    AccM3 : {
        _8 : {
            SCO : {start: 26, len : 1, def : ' ' },
            REC : {start: 26, len : 1, def : ' ' }
        },
        _6 : {
            SCO : {start: 9, len : 1, def : ' ' },
            REC : {start: 9, len : 1, def : ' ' }
        }
    },
    AccM4 : {
        _8 : {
            SCO : {start: 27, len : 1, def : ' ' },
            REC : {start: 27, len : 1, def : ' ' }
        },
        _6 : {
            SCO : {start: 10, len : 1, def : ' ' },
            REC : {start: 10, len : 1, def : ' ' }
        }
    },
    AccM5 : {
        _8 : {
            SCO : {start: 28, len : 1, def : ' ' },
            REC : {start: 28, len : 1, def : ' ' }
        },
        _6 : {
            SCO : {start: 11, len : 1, def : ' ' },
            REC : {start: 11, len : 1, def : ' ' }
        }
    },
    AccM6 : {
        _8 : {
            SCO : {start: 29, len : 1, def : ' ' },
            REC : {start: 29, len : 1, def : ' ' }
        },
        _6 : {
            SCO : {start: 12, len : 1, def : ' ' },
            REC : {start: 12, len : 1, def : ' ' }
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
            BKS : {start : 24, len : 4, def : ' ', multivalue : true },
            SER : {start : 25, len : 3, def : ' ', multivalue : true }
        },
        _6 : {
            BKS : {start : 7, len : 4, def : ' ', multivalue : true },
            SER : {start : 8, len : 3, def : ' ', multivalue : true }
        }
    },
    // break out all four Cont characters individually:
    Cont1 : {
        _8 : {
            BKS : {start : 24, len : 1, def : ' ' },
            SER : {start : 25, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 7, len : 1, def : ' ' },
            SER : {start : 8, len : 1, def : ' ' }
        }
    },
    Cont2 : {
        _8 : {
            BKS : {start : 25, len : 1, def : ' ' },
            SER : {start : 26, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 8, len : 1, def : ' ' },
            SER : {start : 9, len : 1, def : ' ' }
        }
    },
    Cont3 : {
        _8 : {
            BKS : {start : 26, len : 1, def : ' ' },
            SER : {start : 27, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 9, len : 1, def : ' ' },
            SER : {start : 10, len : 1, def : ' ' }
        }
    },
    Cont4 : {
        _8 : {
            BKS : {start : 27, len : 1, def : ' ' },
            SER : {start : 28, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 10, len : 1, def : ' ' },
            SER : {start : 11, len : 1, def : ' ' }
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
            BKS : {start : 18, len : 4, def : ' ', multivalue : true }
        },
        _6 : {
            BKS : {start : 1, len : 4, def : ' ', multivalue : true }
        }
    },
    // break out all four Ills characters individually:
    Ills1 : {
        _8 : {
            BKS : {start : 18, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 1, len : 1, def : ' ' }
        }
    },
    Ills2 : {
        _8 : {
            BKS : {start : 19, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 2, len : 1, def : ' ' }
        }
    },
    Ills3 : {
        _8 : {
            BKS : {start : 20, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 3, len : 1, def : ' ' }
        }
    },
    Ills4 : {
        _8 : {
            BKS : {start : 21, len : 1, def : ' ' }
        },
        _6 : {
            BKS : {start : 4, len : 1, def : ' ' }
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
            SCO : {start : 30, len : 2, def : 'n', multivalue : true },
            REC : {start : 30, len : 2, def : ' ', multivalue : true }
        },
        _6 : {
            SCO : {start : 13, len : 2, def : 'n', multivalue : true },
            REC : {start : 13, len : 2, def : ' ', multivalue : true }
        },
    },
    // break out the two LTxt characters individually:
    LTxt1 : {
        _8 : {
            SCO : {start : 30, len : 1, def : 'n'},
            REC : {start : 30, len : 1, def : ' '}
        },
        _6 : {
            SCO : {start : 13, len : 1, def : 'n'},
            REC : {start : 13, len : 1, def : ' '}
        },
    },
    LTxt2 : {
        _8 : {
            SCO : {start : 31, len : 1, def : 'n'},
            REC : {start : 31, len : 1, def : ' '}
        },
        _6 : {
            SCO : {start : 14, len : 1, def : 'n'},
            REC : {start : 14, len : 1, def : ' '}
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
            MAP : {start: 18, len : 4, def : ' ', multivalue : true }
        },
        _6 : {
            MAP : {start: 1, len : 4, def : ' ', multivalue : true }
        }
    },
    // break out all four Relf characters individually:
    Relf1 : {
        _8 : {
            MAP : {start: 18, len : 1, def : ' ' }
        },
        _6 : {
            MAP : {start: 1, len : 1, def : ' ' }
        }
    },
    Relf2 : {
        _8 : {
            MAP : {start: 19, len : 1, def : ' ' }
        },
        _6 : {
            MAP : {start: 2, len : 1, def : ' ' }
        }
    },
    Relf3 : {
        _8 : {
            MAP : {start: 20, len : 1, def : ' ' }
        },
        _6 : {
            MAP : {start: 3, len : 1, def : ' ' }
        }
    },
    Relf4 : {
        _8 : {
            MAP : {start: 21, len : 1, def : ' ' }
        },
        _6 : {
            MAP : {start: 4, len : 1, def : ' ' }
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
            MAP : {start: 33, len : 2, def : ' ', multivalue : true }
        },
        _6 : {
            MAP : {start: 16, len : 2, def : ' ', multivalue : true }
        }
    },
    // break out the two SpFM characters individually:
    SpFM1 : {
        _8 : {
            MAP : {start: 33, len : 1, def : ' ' }
        },
        _6 : {
            MAP : {start: 16, len : 1, def : ' ' }
        }
    },
    SpFM2 : {
        _8 : {
            MAP : {start: 34, len : 1, def : ' ' }
        },
        _6 : {
            MAP : {start: 17, len : 1, def : ' ' }
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

