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
	dojo.require("dijit._Widget");
	dojo.require("dijit._Templated");
	dojo.require("dijit.layout.ContentPane");
	dojo.require("dijit.Dialog");
	dojo.require("dijit.form.Button");
	dojo.require("dijit.form.TextBox");
	dojo.require("dijit.form.ComboBox");


    dojo.declare('openils.I18N', null, {});

    openils.I18N.BaseLocales = {
		"en" : "English",
		"en_us" : "US English",
		"en_ca" : "Canadian English",
		"es" : "Spanish",
		"es_us" : "US Spanish",
		"fr" : "French",
		"fr_ca" : "Canadian French"
	};

	openils.I18N.localeStore = new dojo.data.ItemFileWriteStore( { data : {identifier : 'locale', label : 'label', items : [] } } );

	for (var i in openils.I18N.BaseLocales) {
		openils.I18N.localeStore.newItem({ locale : i, label : openils.I18N.BaseLocales[i] });
	}

	openils.I18N.getTranslations = function ( obj /* Fieldmapper object */,  field /* Field to translate */, locale /* optional locale */) {
		var classname = obj.classname;

		// XXX need to derive identity field from IDL...
		var ident_field = fieldmapper[classname].Identifier || 'id';
		var ident_value = obj[ident_field]();

		var fielder_args = { query : { fq_field : classname + '.' + field, identity_value : ident_value } };
		if (locale) fielder_args.translation = locale;

		var hash_list = fieldmapper.standardRequest( [ 'open-ils.fielder', 'open-ils.fielder.i18n.atomic'], [ fielder_args ] );
		var obj_list = dojo.map( hash_list, function (t) { return new fieldmapper.i18n().fromHash( t ) } );

		if (locale) return obj_list[0];
		return obj_list;
	}

//----------------------------------------------------------------

    dojo.declare(
		'openils.I18N.translationWidget',
		[dijit._Widget, dijit._Templated],
		{

			templateString : "<span dojoAttachPoint='node'><div dojoType='dijit.form.DropDownButton'><span>Translate</span><div id='${field}_translation' dojoType='dijit.TooltipDialog' onOpen='openils.I18N.translationWidget.renderTranslationPopup(${targetObject}, \"${field}\")' ><div dojoType='dijit.layout.ContentPane'><table><tbody class='translation_tbody_template' style='display:none; visiblity:hidden;'><tr><th>Locale</th><td class='locale'><div class='locale_combobox'></div></td><th>Translation</th><td class='translation'><div class='translation_textbox'></div></td><td><button class='create_button' style='display:none; visiblity:hidden;'>Create</button><button class='update_button' style='display:none; visiblity:hidden;'>Update</button><button class='delete_button' style='display:none; visiblity:hidden;'>Remove</button></td></tr></tbody><tbody class='translation_tbody'></tbody></table></div></div></div></span>",

			widgetsInTemplate: true,
			field : "",
			targetObject : ""
		}
	);

	openils.I18N.translationWidget.renderTranslationPopup = function (obj, field) {
		var node = dojo.byId(field + '_translation');

		var trans_list = openils.I18N.getTranslations( obj, field );

		var trans_template = dojo.query('.translation_tbody_template', node)[0];
		var trans_tbody = dojo.query('.translation_tbody', node)[0];

		// Empty it
		while (trans_tbody.lastChild) trans_tbody.removeChild( trans_tbody.lastChild );

		for (var i in trans_list) {
			if (!trans_list[i]) continue;

			var trans_obj = trans_list[i];
			var trans_id = trans_obj.id();

			var trans_row = dojo.query('tr',trans_template)[0].cloneNode(true);
			trans_row.id = 'translation_row_' + trans_id;

			var old_dijit = dijit.byId('locale_' + trans_id);
			if (old_dijit) old_dijit.destroy();

			old_dijit = dijit.byId('translation_' + trans_id);
			if (old_dijit) old_dijit.destroy();

			dojo.query('.locale_combobox',trans_row).instantiate(
				dijit.form.ComboBox,
				{ store:openils.I18N.localeStore,
				  searchAttr:'locale',
				  lowercase:true,
				  required:true,
				  id:'locale_' + trans_id,
				  value: trans_obj.translation(),
				  invalidMessage:'Specify locale as {languageCode}_{countryCode}, like en_us',
				  regExp:'[a-z_]+'
				}
			);

			dojo.query('.translation_textbox',trans_row).instantiate(
				dijit.form.TextBox,
				{ required : true,
				  id:'translation_' + trans_id,
				  value: trans_obj.string()
				}
			);

			dojo.query('.update_button',trans_row).style({ visibility : 'visible', display : 'inline'}).instantiate(
				dijit.form.Button,
				{ onClick :
					(function (trans_id, obj, field) {
						return function () { openils.I18N.translationWidget.updateTranslation(trans_id, obj, field) }
					})(trans_id, obj, field) 
				}
			);

			dojo.query('.delete_button',trans_row).style({ visibility : 'visible', display : 'inline'}).instantiate(
				dijit.form.Button,
				{ onClick :
					(function (trans_id, obj, field) {
						return function () { openils.I18N.translationWidget.removeTranslation(trans_id, obj, field) }
					})(trans_id, obj, field) 
				}
			);

			trans_tbody.appendChild( trans_row );
		}

		old_dijit = dijit.byId('i18n_new_locale_' + obj.classname + '.' + field);
		if (old_dijit) old_dijit.destroy();

		old_dijit = dijit.byId('i18n_new_translation_' + obj.classname + '.' + field);
		if (old_dijit) old_dijit.destroy();

		trans_row = dojo.query('tr',trans_template)[0].cloneNode(true);

		dojo.query('.locale_combobox',trans_row).instantiate(
			dijit.form.ComboBox,
			{ store:openils.I18N.localeStore,
			  searchAttr:'locale',
			  id:'i18n_new_locale_' + obj.classname + '.' + field,
			  lowercase:true,
			  required:true,
			  invalidMessage:'Specify locale as {languageCode}_{countryCode}, like en_us',
			  regExp:'[a-z_]+'
			}
		);

		dojo.query('.translation_textbox',trans_row).addClass('new_translation').instantiate(
			dijit.form.TextBox,
			{ required : true,
			  id:'i18n_new_translation_' + obj.classname + '.' + field
			}
		);

		dojo.query('.create_button',trans_row).style({ visibility : 'visible', display : 'inline'}).instantiate(
			dijit.form.Button,
			{ onClick : function () { openils.I18N.translationWidget.createTranslation( obj, field) } }
		);

		trans_tbody.appendChild( trans_row );
	}

	openils.I18N.translationWidget.updateTranslation = function (trans_id, obj, field) {
		return openils.I18N.translationWidget.changeTranslation('update', trans_id, obj, field);
	}
	
	openils.I18N.translationWidget.removeTranslation = function (trans_id, obj, field) {
		return openils.I18N.translationWidget.changeTranslation('delete', trans_id, obj, field);
	}
	
	openils.I18N.translationWidget.changeTranslation = function (method, trans_id, obj, field) {
	
		var trans_obj = new i18n().fromHash({
			ischanged : method == 'update' ? 1 : 0,
			isdeleted : method == 'delete' ? 1 : 0,
			id : trans_id,
			fq_field : obj.classname + '.' + field,
			identity_value : obj.id(),
			translation : dijit.byId('locale_' + trans_id).getValue(),
			string : dijit.byId('translation_' + trans_id).getValue()
		});
	
		openils.I18N.translationWidget.writeTranslation(method, trans_obj, obj, field);
	}
	
	openils.I18N.translationWidget.createTranslation = function (obj, field) {
		var node = dojo.byId(field + '_translation');
	
		var trans_obj = new i18n().fromHash({
			isnew : 1,
			fq_field : obj.classname + '.' + field,
			identity_value : obj.id(),
			translation : dijit.byId('i18n_new_locale_' + obj.classname + '.' + field).getValue(),
			string : dijit.byId('i18n_new_translation_' + obj.classname + '.' + field).getValue()
		});
	
		openils.I18N.translationWidget.writeTranslation('create', trans_obj, obj, field);
	}
	
	openils.I18N.translationWidget.writeTranslation = function (method, trans_obj, obj, field) {
	
		OpenSRF.CachedClientSession('open-ils.permacrud').request({
			method : 'open-ils.permacrud.' + method + '.i18n',
			timeout: 10,
			params : [ ses, trans_obj ],
			onerror: function (r) {
				//highlighter.editor_pane.red.play();
				if (status_update) status_update( 'Problem saving translation for ' + obj[field]() );
			},
			oncomplete : function (r) {
				var res = r.recv();
				if ( res && res.content() ) {
					//highlighter.editor_pane.green.play();
					if (status_update) status_update( 'Saved changes to translation for ' + obj[field]() );
	
					if (method == 'delete') {
						dojo.NodeList(dojo.byId('translation_row_' + trans_obj.id())).orphan();
					} else if (method == 'create') {
						var node = dojo.byId(field + '_translation');
						dijit.byId('i18n_new_locale_' + obj.classname + '.' + field).setValue(null);
						dijit.byId('i18n_new_translation_' + obj.classname + '.' + field).setValue(null);
						openils.I18N.translationWidget.renderTranslationPopup(obj, field);
					}
	
				} else {
					//highlighter.editor_pane.red.play();
					if (status_update) status_update( 'Problem saving translation for ' + obj[field]() );
				}
			},
		}).send();
	}

}


