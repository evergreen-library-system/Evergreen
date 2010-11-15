/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * Copyright (C) 2008  Equinox Software, Inc
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

if(!dojo._hasResource["openils.I18N"]) {

    dojo._hasResource["openils.I18N"] = true;
    dojo.provide("openils.I18N");
	dojo.require("dojo.cookie");
	dojo.require("dojo.data.ItemFileWriteStore");
    dojo.require("DojoSRF");
    dojo.require("fieldmapper.Fieldmapper");

    dojo.declare('openils.I18N', null, {});

	var x = dojo.cookie('I18Nset');
	if (x) {
		openils.I18N.BaseLocales = dojo.fromJson(x);
	} else {
		openils.I18N.BaseLocales = fieldmapper.standardRequest( [ 'open-ils.fielder', 'open-ils.fielder.i18n_l.atomic'], [ { cache : 1, query : { code : { '!=' :  null }  } } ] );
		dojo.cookie(
			'I18Nset',
			dojo.toJson(openils.I18N.BaseLocales),
			{ path : location.href.replace(/^https?:\/\/[^\/]+(\/.*\w{2}-\w{2}\/).*/, "$1") }
		);
	}

	openils.I18N.localeStore = new dojo.data.ItemFileWriteStore( { data : {identifier : 'locale', label : 'label', items : [] } } );
	openils.I18N.BaseLocales = openils.I18N.BaseLocales.sort(
        function(a, b) {
            if(a.name > b.name) return 1;
            if(a.name < b.name) return -1;
            return 0;
        }
    );

	for (var i = 0; i < openils.I18N.BaseLocales.length; i++) {
		openils.I18N.localeStore.newItem({ locale : openils.I18N.BaseLocales[i].code, label : openils.I18N.BaseLocales[i].name });
	}

	openils.I18N.getTranslations = function ( obj /* Fieldmapper object */,  field /* Field to translate */, locale /* optional locale */) {
		var classname = obj.classname;

		// XXX need to derive identity field from IDL...
		var ident_field = fieldmapper[classname].Identifier;
		var ident_value = obj[ident_field]();

		var fielder_args = { query : { fq_field : classname + '.' + field, identity_value : ident_value } };
		if (locale) fielder_args.translation = locale;

		var hash_list = fieldmapper.standardRequest( [ 'open-ils.fielder', 'open-ils.fielder.i18n.atomic'], [ fielder_args ] );
		var obj_list = dojo.map( hash_list, function (t) { return new fieldmapper.i18n().fromHash( t ) } );

		if (locale) return obj_list[0];
		return obj_list;
	}

    openils.I18N.translatePage = function () {

        dojo.require('dojo.query');

        var elements = dojo.query('*[i18n]');
        if (!elements.length) return null;

        dojo.forEach(elements, function(e){

            var what = e.getAttribute('i18n');
            var parts = what.match(/^(.+)\.([^.]+)$/);
            var app = parts[0]; var bundle = parts[1];
            if (!app || !bundle) return null;

            if (!openils.I18N.translatePage.NLSCache[app][bundle]) {
                dojo.requireLocalization(app,bundle);
                openils.I18N.translatePage.NLSCache[app][bundle] = dojo.i18n.getLocalization(app,bundle);

                if (!openils.I18N.translatePage.NLSCache[app][bundle]) return null;
            }

            dojo.require('dojo.string');

            var template = e.innerHTML;
            var finalHTML = dojo.string.substitute( template, openils.I18N.translatePage.NLSCache[app][bundle] );

            if (template == finalHTML) { // no subsititution occurred
                dojo.require("dojox.jsonPath");
                var transString = e.getAttribute('string') || template;
                finalHTML = dojox.jsonPath.query(
                    openils.I18N.translatePage.NLSCache[app][bundle],
                    '$.'+transString,
                    {evalType:"RESULT"}
                );
            }

            if (finalHTML) e.innerHTML = finalHTML;

        });
    }
    openils.I18N.translatePage.NLSCache = {}; // stash this on the function .. WHEEEE

}


