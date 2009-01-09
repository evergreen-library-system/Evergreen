/*
# ---------------------------------------------------------------------------
# Copyright (C) 2008  Georgia Public Library Service / Equinox Software, Inc
# Mike Rylander <miker@esilibrary.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------------------
*/

if(!dojo._hasResource["fieldmapper.Fieldmapper"]){

/* generate fieldmapper javascript classes.  This expects a global variable
	called 'fmclasses' to be fleshed with the classes we need to build */

	function FMEX(message) { this.message = message; }
	FMEX.toString = function() { return "FieldmapperException: " + this.message + "\n"; }


	dojo._hasResource["fieldmapper.Fieldmapper"] = true;
	dojo.provide("fieldmapper.Fieldmapper");
	dojo.require("DojoSRF");

	dojo.declare( "fieldmapper.Fieldmapper", null, {

		constructor : function (initArray) {
			if (initArray) {
				if (dojo.isArray(initArray)) {
					this.a = initArray;
				} else {
					this.a = [];
				}
			}
		},

		_isfieldmapper : true,

		clone : function() {
			var obj = new this.constructor();

			for( var i in this.a ) {
				var thing = this.a[i];
				if(thing == null) continue;

				if( thing._isfieldmapper ) {
					obj.a[i] = thing.clone();
				} else {

					if(instanceOf(thing, Array)) {
						obj.a[i] = new Array();

						for( var j in thing ) {

							if( thing[j]._isfieldmapper )
								obj.a[i][j] = thing[j].clone();
							else
								obj.a[i][j] = thing[j];
						}
					} else {
						obj.a[i] = thing;
					}
				}
			}
			return obj;
		},

		isnew : function(n) { if(arguments.length == 1) this.a[0] =n; return this.a[0]; },
		ischanged : function(n) { if(arguments.length == 1) this.a[1] =n; return this.a[1]; },
		isdeleted : function(n) { if(arguments.length == 1) this.a[2] =n; return this.a[2]; }
	});

	fieldmapper._request = function ( meth, staff, params ) {
		var ses = OpenSRF.CachedClientSession( meth[0] );
		if (!ses) return null;

		var result = null;
		var args = {};

		if (dojo.isArray(params)) {
			args.params = params;
		} else {

			if (dojo.isObject(params)) {
				args = params;
			} else {
                args.params = [].splice.call(arguments, 1, arguments.length - 1);
			}

		}

        if (!args.async && !args.timeout) args.timeout = 10;

        if(!args.onmethoderror) {
            args.onmethoderror = function(r, stat, stat_text) {
                throw new Error('Method error: ' + r.stat + ' : ' + stat_text);
            }
        }

        if(!args.ontransporterror) {
            args.ontransporterror = function(xreq) {
                throw new Error('Transport error method='+args.method+', status=' + xreq.status);
            }
        }

		if (!args.onerror) {
			args.onerror = function (r) {
				throw new Error('Request error encountered! ' + r);
			}
		}

		if (!args.oncomplete) {
			args.oncomplete = function (r) {
				var x = r.recv();
				if (x) result = x.content();
			}
		}

		args.method = meth[1];
		if (staff && meth[2]) args.method += '.staff';

		ses.request(args).send();

		return result;
	};

	fieldmapper.standardRequest = function (meth, params) { return fieldmapper._request(meth, false, params) };
	fieldmapper.Fieldmapper.prototype.standardRequest = fieldmapper.standardRequest;

	fieldmapper.staffRequest = function (meth, params) { return fieldmapper._request(meth, true, params) };
	fieldmapper.Fieldmapper.prototype.staffRequest = fieldmapper.staffRequest;

    // if we were called by the IDL loader ...
    if ( fieldmapper.IDL && fieldmapper.IDL.loaded ) {
    	for( var cl in fieldmapper.IDL.fmclasses ) {
    		dojo.provide( cl );
    		dojo.declare( cl , fieldmapper.Fieldmapper, {
    			constructor : function () {
    				if (!this.a) this.a = [];
    				this.classname = this.declaredClass;
                    this._fields = [];
                    this.Structure = fieldmapper.IDL.fmclasses[this.classname]

                    for (var f in fieldmapper.IDL.fmclasses[this.classname].fields) {
                        var field = fieldmapper.IDL.fmclasses[this.classname].fields[f];
                        var p = field.array_position;
                        if (p > 2) continue;

        				this._fields.push( field.name );
    					this[field.name]=new Function('n', 'if(arguments.length==1)this.a['+p+']=n;return this.a['+p+'];');
                    }
    			}
    		});
    		fieldmapper[cl] = window[cl]; // alias into place
    		fieldmapper[cl].Identifier = fieldmapper.IDL.fmclasses[cl].pkey;
    	}

    // ... otherwise we need to get the oldschool fmall.js stuff, which will lack .structure
    } else {
    	if (!window.fmclasses)
            dojo.require("fieldmapper.fmall", true);

    	for( var cl in fmclasses ) {
    		dojo.provide( cl );
    		dojo.declare( cl , fieldmapper.Fieldmapper, {
    			constructor : function () {
    				if (!this.a) this.a = [];
    				this.classname = this.declaredClass;
    				this._fields = fmclasses[this.classname];
    				for( var pos = 0; pos <  this._fields.length; pos++ ) {
    					var p = parseInt(pos) + 3;
    					var f = this._fields[pos];
    					this[f]=new Function('n', 'if(arguments.length==1)this.a['+p+']=n;return this.a['+p+'];');
    				}
    			}
    		});
    		fieldmapper[cl] = window[cl]; // alias into place
    		fieldmapper[cl].Identifier = 'id'; // alias into place
    	}

    	fieldmapper.i18n_l.Identifier = 'code';
    	fieldmapper.ccpbt.Identifier = 'code';
    	fieldmapper.ccnbt.Identifier = 'code';
    	fieldmapper.cbrebt.Identifier = 'code';
    	fieldmapper.cubt.Identifier = 'code';
    	fieldmapper.ccm.Identifier = 'code';
    	fieldmapper.cvrfm.Identifier = 'code';
    	fieldmapper.clm.Identifier = 'code';
    	fieldmapper.cam.Identifier = 'code';
    	fieldmapper.cifm.Identifier = 'code';
    	fieldmapper.citm.Identifier = 'code';
    	fieldmapper.cblvl.Identifier = 'code';
    	fieldmapper.clfm.Identifier = 'code';
    	fieldmapper.mous.Identifier = 'usr';
    	fieldmapper.moucs.Identifier = 'usr';
    	fieldmapper.mucs.Identifier = 'usr';
    	fieldmapper.mus.Identifier = 'usr';
    	fieldmapper.rxbt.Identifier = 'xact';
    	fieldmapper.rxpt.Identifier = 'xact';
    	fieldmapper.cxt.Identifier = 'name';
    	fieldmapper.amtr.Identifier = 'matchpoint';

    }

	fieldmapper.OpenSRF = {};

	/*	Methods are defined as [ service, method, have_staff ]
		An optional 3rd component is when a method is followed by true, such methods
		have a staff counterpart and should have ".staff" appended to the method 
		before the method is called when in XUL mode */
	fieldmapper.OpenSRF.methods = {
		SEARCH_MRS : ['open-ils.search','open-ils.search.metabib.multiclass',true],
		SEARCH_RS : ['open-ils.search','open-ils.search.biblio.multiclass',true],
		SEARCH_MRS_QUERY : ['open-ils.search','open-ils.search.metabib.multiclass.query',true],
		SEARCH_RS_QUERY : ['open-ils.search','open-ils.search.biblio.multiclass.query',true],
		FETCH_SEARCH_RIDS : ['open-ils.search','open-ils.search.biblio.record.class.search',true],
		FETCH_MRMODS : ['open-ils.search','open-ils.search.biblio.metarecord.mods_slim.retrieve'],
		FETCH_MODS_FROM_COPY : ['open-ils.search','open-ils.search.biblio.mods_from_copy'],
		FETCH_MR_COPY_COUNTS : ['open-ils.search','open-ils.search.biblio.metarecord.copy_count',true],
		FETCH_RIDS : ['open-ils.search','open-ils.search.biblio.metarecord_to_records',true],
		FETCH_RMODS : ['open-ils.search','open-ils.search.biblio.record.mods_slim.retrieve'],
		FETCH_R_COPY_COUNTS : ['open-ils.search','open-ils.search.biblio.record.copy_count',true],
		FETCH_FLESHED_USER : ['open-ils.actor','open-ils.actor.user.fleshed.retrieve'],
		FETCH_SESSION : ['open-ils.auth','open-ils.auth.session.retrieve'],
		LOGIN_INIT : ['open-ils.auth','open-ils.auth.authenticate.init'],
		LOGIN_COMPLETE : ['open-ils.auth','open-ils.auth.authenticate.complete'],
		LOGIN_DELETE : ['open-ils.auth','open-ils.auth.session.delete'],
		FETCH_USER_PREFS : ['open-ils.actor','open-ils.actor.patron.settings.retrieve'], 
		UPDATE_USER_PREFS : ['open-ils.actor','open-ils.actor.patron.settings.update'], 
		FETCH_COPY_STATUSES : ['open-ils.search','open-ils.search.config.copy_status.retrieve.all'],
		FETCH_COPY_COUNTS_SUMMARY : ['open-ils.search','open-ils.search.biblio.copy_counts.summary.retrieve'],
		FETCH_MARC_HTML : ['open-ils.search','open-ils.search.biblio.record.html'],
		FETCH_CHECKED_OUT_SUM : ['open-ils.actor','open-ils.actor.user.checked_out'],
		FETCH_HOLDS : ['open-ils.circ','open-ils.circ.holds.retrieve'],
		FETCH_FINES_SUMMARY : ['open-ils.actor','open-ils.actor.user.fines.summary'],
		FETCH_TRANSACTIONS : ['open-ils.actor','open-ils.actor.user.transactions.have_charge.fleshed'],
		FETCH_MONEY_BILLING : ['open-ils.circ','open-ils.circ.money.billing.retrieve.all'],
		FETCH_CROSSREF : ['open-ils.search','open-ils.search.authority.crossref'],
		FETCH_CROSSREF_BATCH : ['open-ils.search','open-ils.search.authority.crossref.batch'],
		CREATE_HOLD : ['open-ils.circ','open-ils.circ.holds.create'],
		CREATE_HOLD_OVERRIDE : ['open-ils.circ','open-ils.circ.holds.create.override'],
		CANCEL_HOLD : ['open-ils.circ','open-ils.circ.hold.cancel'],
		UPDATE_USERNAME : ['open-ils.actor','open-ils.actor.user.username.update'],
		UPDATE_PASSWORD : ['open-ils.actor','open-ils.actor.user.password.update'],
		UPDATE_EMAIL : ['open-ils.actor','open-ils.actor.user.email.update'],
		RENEW_CIRC : ['open-ils.circ','open-ils.circ.renew'],
		CHECK_SPELL : ['open-ils.search','open-ils.search.spellcheck'],
		FETCH_REVIEWS : ['open-ils.search','open-ils.search.added_content.review.retrieve.all'],
		FETCH_TOC : ['open-ils.search','open-ils.search.added_content.toc.retrieve'],
		FETCH_ACONT_SUMMARY : ['open-ils.search','open-ils.search.added_content.summary.retrieve'],
		FETCH_USER_BYBARCODE : ['open-ils.actor','open-ils.actor.user.fleshed.retrieve_by_barcode'],
		FETCH_ADV_MARC_MRIDS : ['open-ils.search','open-ils.search.biblio.marc',true],
		FETCH_ADV_ISBN_RIDS : ['open-ils.search','open-ils.search.biblio.isbn'],
		FETCH_ADV_ISSN_RIDS : ['open-ils.search','open-ils.search.biblio.issn'],
		FETCH_ADV_TCN_RIDS : ['open-ils.search','open-ils.search.biblio.tcn'],
		FETCH_CNBROWSE : ['open-ils.search','open-ils.search.callnumber.browse'],
		FETCH_CONTAINERS : ['open-ils.actor','open-ils.actor.container.retrieve_by_class'],
		FETCH_CONTAINERS : ['open-ils.actor','open-ils.actor.container.retrieve_by_class'],
		CREATE_CONTAINER : ['open-ils.actor','open-ils.actor.container.create'],
		DELETE_CONTAINER : ['open-ils.actor','open-ils.actor.container.full_delete'],
		CREATE_CONTAINER_ITEM : ['open-ils.actor','open-ils.actor.container.item.create'],
		DELETE_CONTAINER_ITEM : ['open-ils.actor','open-ils.actor.container.item.delete'],
		FLESH_CONTAINER : ['open-ils.actor','open-ils.actor.container.flesh'],
		FLESH_PUBLIC_CONTAINER : ['open-ils.actor','open-ils.actor.container.public.flesh'],
		UPDATE_CONTAINER : ['open-ils.actor','open-ils.actor.container.update'],
		FETCH_COPY : ['open-ils.search','open-ils.search.asset.copy.retrieve'],
		FETCH_FLESHED_COPY : ['open-ils.search','open-ils.search.asset.copy.fleshed2.retrieve'],
		CHECK_HOLD_POSSIBLE : ['open-ils.circ','open-ils.circ.title_hold.is_possible'],
		UPDATE_HOLD : ['open-ils.circ','open-ils.circ.hold.update'],
		FETCH_COPIES_FROM_VOLUME : ['open-ils.search','open-ils.search.asset.copy.retrieve_by_cn_label',true],
		FETCH_VOLUME_BY_INFO : ['open-ils.search','open-ils.search.call_number.retrieve_by_info'], /* XXX staff method? */
		FETCH_VOLUME : ['open-ils.search','open-ils.search.asset.call_number.retrieve'],
		FETCH_COPY_LOCATIONS : ['open-ils.circ','open-ils.circ.copy_location.retrieve.all'],
		FETCH_COPY_NOTES : ['open-ils.circ','open-ils.circ.copy_note.retrieve.all'],
		FETCH_COPY_STAT_CATS : ['open-ils.circ','open-ils.circ.asset.stat_cat_entries.fleshed.retrieve_by_copy'],
		FETCH_LIT_FORMS : ['open-ils.search','open-ils.search.biblio.lit_form_map.retrieve.all'],
		FETCH_ITEM_FORMS : ['open-ils.search','open-ils.search.biblio.item_form_map.retrieve.all'],
		FETCH_ITEM_TYPES : ['open-ils.search','open-ils.search.biblio.item_type_map.retrieve.all'],
		FETCH_AUDIENCES : ['open-ils.search','open-ils.search.biblio.audience_map.retrieve.all'],
		FETCH_HOLD_STATUS : ['open-ils.circ','open-ils.circ.hold.status.retrieve'],
		FETCH_NON_CAT_CIRCS : ['open-ils.circ','open-ils.circ.open_non_cataloged_circulation.user'],
		FETCH_NON_CAT_CIRC : ['open-ils.circ','open-ils.circ.non_cataloged_circulation.retrieve'],
		FETCH_NON_CAT_TYPES : ['open-ils.circ','open-ils.circ.non_cat_types.retrieve.all'],
		FETCH_BRE : ['open-ils.search','open-ils.search.biblio.record_entry.slim.retrieve'],
		CHECK_USERNAME : ['open-ils.actor','open-ils.actor.username.exists'],
		FETCH_CIRC_BY_ID : ['open-ils.circ','open-ils.circ.retrieve'],
		FETCH_MR_DESCRIPTORS : ['open-ils.search','open-ils.search.metabib.record_to_descriptors'],
		FETCH_HIGHEST_PERM_ORG : ['open-ils.actor','open-ils.actor.user.perm.highest_org.batch'],
		FETCH_USER_NOTES : ['open-ils.actor','open-ils.actor.note.retrieve.all'],
		FETCH_ORG_BY_SHORTNAME : ['open-ils.actor','open-ils.actor.org_unit.retrieve_by_shorname'],
		FETCH_BIB_ID_BY_BARCODE : ['open-ils.search','open-ils.search.bib_id.by_barcode'],
		FETCH_ORG_SETTING : ['open-ils.actor','open-ils.actor.ou_setting.ancestor_default']
	};

}



