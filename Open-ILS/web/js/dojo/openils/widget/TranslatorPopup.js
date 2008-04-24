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

if(!dojo._hasResource["openils.widget.TranslatorPopup"]) {

    dojo._hasResource["openils.widget.TranslatorPopup"] = true;
    dojo.provide("openils.widget.TranslatorPopup");
    dojo.require("openils.I18N");
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
	dojo.requireLocalization("openils.widget", "TranslatorPopup");


    dojo.declare(
		'openils.widget.TranslatorPopup',
		[dijit._Widget, dijit._Templated],
		{

			templateString : "<span dojoAttachPoint='node'><div dojoAttachPoint='translateLabelNode' dojoType='dijit.form.DropDownButton'><span>Translate</span><div id='${field}_translation_${unique}' dojoType='dijit.TooltipDialog' onOpen='openils.widget.TranslatorPopup.renderTranslatorPopup(${targetObject}, \"${field}\", \"${unique}\")' ><div dojoType='dijit.layout.ContentPane'><table><tbody class='translation_tbody_template' style='display:none; visiblity:hidden;'><tr><th dojoAttachPoint='localeLabelNode'/><td class='locale'><div class='locale_combobox'></div></td><th dojoAttachPoint='translationLabelNode'/><td class='translation'><div class='translation_textbox'></div></td><td><button class='create_button' style='display:none; visiblity:hidden;'><span dojoAttachPoint='createButtonNode'/></button><button class='update_button' style='display:none; visiblity:hidden;'><span dojoAttachPoint='updateButtonNode'/></button><button class='delete_button' style='display:none; visiblity:hidden;'><span dojoAttachPoint='removeButtonNode'/></button></td></tr></tbody><tbody class='translation_tbody'></tbody></table></div></div></div></span>",

			widgetsInTemplate: true,
			field : "",
			targetObject : "",
			unique : "",

			postCreate : function () {
				var nls = dojo.i18n.getLocalization("openils.widget", "TranslatorPopup");
				this.localeLabelNode.textContent = nls.locale;
				this.translationLabelNode.textContent = nls.translation;
				this.translateLabelNode.setLabel(nls.translate);
				this.createButtonNode.textContent = nls.create;
				this.updateButtonNode.textContent = nls.update;
				this.removeButtonNode.textContent = nls.remove;
			}
		}
	);

	openils.widget.TranslatorPopup.renderTranslatorPopup = function (obj, field, num) {
		var node = dojo.byId(field + '_translation_' + num);

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
						return function () { openils.widget.TranslatorPopup.updateTranslation(trans_id, obj, field, num) }
					})(trans_id, obj, field) 
				}
			);

			dojo.query('.delete_button',trans_row).style({ visibility : 'visible', display : 'inline'}).instantiate(
				dijit.form.Button,
				{ onClick :
					(function (trans_id, obj, field) {
						return function () { openils.widget.TranslatorPopup.removeTranslation(trans_id, obj, field, num) }
					})(trans_id, obj, field) 
				}
			);

			trans_tbody.appendChild( trans_row );
		}

		old_dijit = dijit.byId('i18n_new_locale_' + obj.classname + '.' + field + num);
		if (old_dijit) old_dijit.destroy();

		old_dijit = dijit.byId('i18n_new_translation_' + obj.classname + '.' + field + num);
		if (old_dijit) old_dijit.destroy();

		trans_row = dojo.query('tr',trans_template)[0].cloneNode(true);

		dojo.query('.locale_combobox',trans_row).instantiate(
			dijit.form.ComboBox,
			{ store:openils.I18N.localeStore,
			  searchAttr:'locale',
			  id:'i18n_new_locale_' + obj.classname + '.' + field + num,
			  lowercase:true,
			  required:true,
			  invalidMessage:'Specify locale as {languageCode}_{countryCode}, like en_us',
			  regExp:'[a-z_]+'
			}
		);

		dojo.query('.translation_textbox',trans_row).addClass('new_translation').instantiate(
			dijit.form.TextBox,
			{ required : true,
			  id:'i18n_new_translation_' + obj.classname + '.' + field + num
			}
		);

		dojo.query('.create_button',trans_row).style({ visibility : 'visible', display : 'inline'}).instantiate(
			dijit.form.Button,
			{ onClick : function () { openils.widget.TranslatorPopup.createTranslation( obj, field, num) } }
		);

		trans_tbody.appendChild( trans_row );
	}

	openils.widget.TranslatorPopup.updateTranslation = function (trans_id, obj, field, num) {
		return openils.widget.TranslatorPopup.changeTranslation('update', trans_id, obj, field, num);
	}
	
	openils.widget.TranslatorPopup.removeTranslation = function (trans_id, obj, field, num) {
		return openils.widget.TranslatorPopup.changeTranslation('delete', trans_id, obj, field, num);
	}
	
	openils.widget.TranslatorPopup.changeTranslation = function (method, trans_id, obj, field, num) {
	
		var trans_obj = new i18n().fromHash({
			ischanged : method == 'update' ? 1 : 0,
			isdeleted : method == 'delete' ? 1 : 0,
			id : trans_id,
			fq_field : obj.classname + '.' + field,
			identity_value : obj.id(),
			translation : dijit.byId('locale_' + trans_id).getValue(),
			string : dijit.byId('translation_' + trans_id).getValue()
		});
	
		openils.widget.TranslatorPopup.writeTranslation(method, trans_obj, obj, field, num);
	}
	
	openils.widget.TranslatorPopup.createTranslation = function (obj, field, num) {
		var node = dojo.byId(field + '_translation_' + num);
	
		var trans_obj = new i18n().fromHash({
			isnew : 1,
			fq_field : obj.classname + '.' + field,
			identity_value : obj.id(),
			translation : dijit.byId('i18n_new_locale_' + obj.classname + '.' + field + num).getValue(),
			string : dijit.byId('i18n_new_translation_' + obj.classname + '.' + field + num).getValue()
		});
	
		openils.widget.TranslatorPopup.writeTranslation('create', trans_obj, obj, field, num);
	}
	
	openils.widget.TranslatorPopup.writeTranslation = function (method, trans_obj, obj, field, num) {
	
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
						var node = dojo.byId(field + '_translation_' + num);
						dijit.byId('i18n_new_locale_' + obj.classname + '.' + field + num).setValue(null);
						dijit.byId('i18n_new_translation_' + obj.classname + '.' + field + num).setValue(null);
						openils.widget.TranslatorPopup.renderTranslatorPopup(obj, field, num);
					}
	
				} else {
					//highlighter.editor_pane.red.play();
					if (status_update) status_update( 'Problem saving translation for ' + obj[field]() );
				}
			},
		}).send();
	}

}


