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
    dojo.require("fieldmapper.dojoData");
    dojo.require("DojoSRF");
	dojo.require("dojo.data.ItemFileWriteStore");

    dojo.declare('openils.I18N', null, {});

	openils.I18N.BaseLocales = fieldmapper.standardRequest( [ 'open-ils.fielder', 'open-ils.fielder.i18n_l.atomic'], [ { query : { code : { '!=' :  null }  } } ] );
	openils.I18N.localeStore = new dojo.data.ItemFileWriteStore( { data : {identifier : 'locale', label : 'label', items : [] } } );

	for (var i in openils.I18N.BaseLocales) {
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

}


