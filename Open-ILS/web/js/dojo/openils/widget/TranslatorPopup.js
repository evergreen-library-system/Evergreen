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
	dojo.require("dijit.form.FilteringSelect");
	dojo.require("dojox.jsonPath");
    dojo.require('openils.XUL');
	dojo.requireLocalization("openils.widget", "TranslatorPopup");


    dojo.declare(
		'openils.widget.TranslatorPopup',
		[dijit._Widget, dijit._Templated],
		{

			templateString : "<span id='${field}_translation_${unique}' dojoAttachPoint='containerNode'><div id='${field}_translation_button_${unique}' dojoAttachPoint='translateLabelNode' dojoType='dijit.form.DropDownButton'><span>Translate</span><div id='${field}_translation_tooltip_${unique}' dojoAttachPoint='tooltipDialog' dojoType='dijit.TooltipDialog'><div dojoType='dijit.layout.ContentPane'><table><tbody class='translation_tbody_template' style='display:none; visibility:hidden;'><tr><th dojoAttachPoint='localeLabelNode'/><td class='locale'><div class='locale_combobox'></div></td><th dojoAttachPoint='translationLabelNode'/><td class='translation'><div class='translation_textbox'></div></td><td><button class='create_button' style='display:none; visibility:hidden;'><span dojoAttachPoint='createButtonNode'></span></button><button class='update_button' style='display:none; visibility:hidden;'><span dojoAttachPoint='updateButtonNode'></span></button><button class='delete_button' style='display:none; visibility:hidden;'><span dojoAttachPoint='removeButtonNode'></span></button></td></tr></tbody><tbody class='translation_tbody'></tbody></table></div></div></div></span>",

			widgetsInTemplate: true,
			field : "",
			targetObject : "",
			unique : "",

			postMixInProperties : function () {
				if (!this.unique) this.unique = openils.widget.TranslatorPopup._unique++;
			},

			postCreate : function () {

				dojo.connect(this.tooltipDialog, 'onOpen', this, 'renderTranslatorPopup');

				this.nls = dojo.i18n.getLocalization("openils.widget", "TranslatorPopup");

				this.translateLabelNode.setLabel(this.nls.translate);

				this.localeLabelNode.textContent = this.nls.locale;
				this.translationLabelNode.textContent = this.nls.translation;

				this.createButtonNode.textContent = this.nls.create;
				this.updateButtonNode.textContent = this.nls.update;
				this.removeButtonNode.textContent = this.nls.remove;
			},

			renderTranslatorPopup : function () {

				var _trans_dijit = this;

				this._targetObject = dojox.jsonPath.query(window, '$.' + this.targetObject, {evalType:"RESULT"});

				var node = dojo.byId(this.field + '_translation_tooltip_' + this.unique);
		
				var trans_list = openils.I18N.getTranslations( this._targetObject, this.field );
		
				var trans_template = dojo.query('.translation_tbody_template', node)[0];
				var trans_tbody = dojo.query('.translation_tbody', node)[0];
		
				// Empty it
				while (trans_tbody.lastChild) trans_tbody.removeChild( trans_tbody.lastChild );
		
				for (var i = 0; i < trans_list.length; i++) {
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
						dijit.form.FilteringSelect,
						{ store:openils.I18N.localeStore,
						  searchAttr:'locale',
						  labelAttr:'label',
						  lowercase:false,
						  required:true,
						  id:'locale_' + trans_id,
						  value: trans_obj.translation(),
						  invalidMessage:'Specify locale as {languageCode}-{countryCode}, as in en-US',
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
						{ onClick : dojo.hitch( _trans_dijit, 'updateTranslation', trans_id) }
					);
		
					dojo.query('.delete_button',trans_row).style({ visibility : 'visible', display : 'inline'}).instantiate(
						dijit.form.Button,
						{ onClick : dojo.hitch( _trans_dijit, 'removeTranslation', trans_id) }
					);
		
					trans_tbody.appendChild( trans_row );
		
				}
		
				old_dijit = dijit.byId('i18n_new_locale_' + this._targetObject.classname + '.' + this.field + this.unique);
				if (old_dijit) old_dijit.destroy();
		
				old_dijit = dijit.byId('i18n_new_translation_' + this._targetObject.classname + '.' + this.field + this.unique);
				if (old_dijit) old_dijit.destroy();
		
				trans_row = dojo.query('tr',trans_template)[0].cloneNode(true);
		
				dojo.query('.locale_combobox',trans_row).instantiate(
					dijit.form.FilteringSelect,
					{ store:openils.I18N.localeStore,
					  searchAttr:'locale',
					  labelAttr:'label',
					  id:'i18n_new_locale_' + this._targetObject.classname + '.' + this.field + this.unique,
					  lowercase:false,
					  required:true,
					  invalidMessage:'Specify locale as {languageCode}_{countryCode}, as in en-US',
					  regExp:'[a-z_]+'
					}
				);
		
				dojo.query('.translation_textbox',trans_row).addClass('new_translation').instantiate(
					dijit.form.TextBox,
					{ required : true,
					  id:'i18n_new_translation_' + this._targetObject.classname + '.' + this.field + this.unique
					}
				);
		
				dojo.query('.create_button',trans_row).style({ visibility : 'visible', display : 'inline'}).instantiate(
					dijit.form.Button,
					{ onClick : dojo.hitch( _trans_dijit, 'createTranslation') }
				);
		
				trans_tbody.appendChild( trans_row );

			},

			updateTranslation : function (t) {
				return this.changeTranslation('update',t);
			},
			
			removeTranslation : function (t) {
				return this.changeTranslation('delete',t);
			},
			
			changeTranslation : function (method, trans_id) {
			
				var trans_obj = new i18n().fromHash({
					ischanged : method == 'update' ? 1 : 0,
					isdeleted : method == 'delete' ? 1 : 0,
					id : trans_id,
					fq_field : this._targetObject.classname + '.' + this.field,
					identity_value : this._targetObject[fieldmapper[this._targetObject.classname].Identifier](),
					translation : dijit.byId('locale_' + trans_id).getValue(),
					string : dijit.byId('translation_' + trans_id).getValue()
				});
			
				this.writeTranslation(method, trans_obj);
			},
			
			createTranslation : function () {
				var node = dojo.byId(this.field + '_translation_tooltip_' + this.unique);
			
				var trans_obj = new i18n().fromHash({
					isnew : 1,
					fq_field : this._targetObject.classname + '.' + this.field,
					identity_value : this._targetObject[fieldmapper[this._targetObject.classname].Identifier](),
					translation : dijit.byId('i18n_new_locale_' + this._targetObject.classname + '.' + this.field + this.unique).getValue(),
					string : dijit.byId('i18n_new_translation_' + this._targetObject.classname + '.' + this.field + this.unique).getValue()
				});
			
				this.writeTranslation('create', trans_obj);
			},
	
			writeTranslation : function (method, trans_obj) {
			
				var _trans_dijit = this;

                if (typeof(ses) == "undefined") {
                    var ses = cgi.param("ses") || dojo.cookie("ses");
                    if(!ses && openils.XUL.isXUL()) {
                        var stash = openils.XUL.getStash();
                        ses = stash.session.key;
                    }
                }

				OpenSRF.CachedClientSession('open-ils.permacrud').request({
					method : 'open-ils.permacrud.' + method + '.i18n',
					timeout: 10,
					params : [ ses, trans_obj ],
					onerror: function (r) {
						//highlighter.editor_pane.red.play();
						if ((typeof status_update != "undefined") && status_update) status_update( 'Problem saving translation for ' + _trans_dijit._targetObject[_trans_dijit.field]() );
					},
					oncomplete : function (r) {
						var res = r.recv();
						if ( res && res.content() ) {
							//highlighter.editor_pane.green.play();
							if ((typeof status_update != "undefined") && status_update) status_update( 'Saved changes to translation for ' + _trans_dijit._targetObject[_trans_dijit.field]() );
			
							if (method == 'delete') {
								dojo.NodeList(dojo.byId('translation_row_' + trans_obj.id())).orphan();
							} else if (method == 'create') {
								var node = dojo.byId(_trans_dijit.field + '_translation_tooltip_' + _trans_dijit.unique);
								dijit.byId('i18n_new_locale_' + _trans_dijit._targetObject.classname + '.' + _trans_dijit.field + _trans_dijit.unique).setValue(null);
								dijit.byId('i18n_new_translation_' + _trans_dijit._targetObject.classname + '.' + _trans_dijit.field + _trans_dijit.unique).setValue(null);
								_trans_dijit.renderTranslatorPopup();
							}
			
						} else {
							//highlighter.editor_pane.red.play();
							if ((typeof status_update != "undefined") && status_update) status_update( 'Problem saving translation for ' + _trans_dijit._targetObject[_trans_dijit.field]() );
						}
					},
				}).send();
			}

		}

	);

	openils.widget.TranslatorPopup._unique = 1;



}


