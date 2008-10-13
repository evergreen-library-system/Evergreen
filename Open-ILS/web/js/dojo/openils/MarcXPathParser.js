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

if(!dojo._hasResource["openils.MarcXPathParser"]) {
    dojo._hasResource["openils.MarcXPathParser"] = true;
    dojo.provide("openils.MarcXPathParser");

    dojo.declare('openils.MarcXPathParser', null, {
        /**
          * Parse a marc xpath expression and return the breakdown of tags, subfields, and match offset
          */
        parse : function(expr) {
            // this is about as simple as it gets. will need more 
            // smarts if the expressions get more complicated
            var tags = expr.match(/\d{3}/g);
            var subfields = expr.match(/['"]([a-z]+)['"]/);
            var offset = expr.match(/\[(\d+)\]$/);
            return {
                tags : tags,
                subfields : (subfields) ? subfields[1].split('') : [],
                offset : (offset) ? offset[1] : null
            }
        },

        /**
          * Creates an XPath expression from a set of tags/subfields/offset
          */
        compile : function(parts) {
            var str = '//*[';
            for(var i = 0; i < parts.tags.length; i++) {
                var tag = parts.tags[i];
                if(i > 0)
                    str += ' or ';
                str += '@tag="'+tag+'"';
            }
            str += ']';
            if(parts.subfields.length > 0) {
                str += '/*[';
                if(parts.subfields.length == 1) {
                    str += '@code="' + parts.subfields[0] + '"]';
                } else {
                    str += 'contains("' + parts.subfields.join('') +'",@code)]';
                }
            }
            if(parts.offset)
                str += '[' + parts.offset + ']';
            return str;
        }
    });
}


openils.MarcXPathParser.test = function() {
    var expr = [
        '//*[@tag="300"]/*[@code="a"][1]',
        '//*[@tag="020"]/*[@code="a"]',
        '//*[@tag="022"]/*[@code="a"]',
        '//*[@tag="020" or @tag="022"]/*[@code="c"][1]',
        '//*[@tag="001"]',
        '//*[@tag="901"]/*[@code="a"]',
        '//*[@tag="901"]/*[@code="b"]',
        '//*[@tag="901"]/*[@code="c"]',
        '//*[@tag="260"]/*[@code="b"][1]',
        '//*[@tag="250"]/*[@code="a"][1]',
        '//*[@tag="245"]/*[contains("abcmnopr",@code)]',
        '//*[@tag="260"]/*[@code="c"][1]',
        '//*[@tag="100" or @tag="110" or @tag="113"]/*[contains("ad",@code)]',
        '//*[@tag="240"]/*[@code="l"][1]'
    ];

    var parser = new openils.MarcXPathParser();

    for(var i = 0; i < expr.length; i++) {
        var vals = parser.parse(expr[i]);
        console.log(expr[i]);
        console.log(vals.tags);
        console.log(vals.subfields);
        console.log(vals.offset);
        console.log(parser.compile(vals));
    }
};

