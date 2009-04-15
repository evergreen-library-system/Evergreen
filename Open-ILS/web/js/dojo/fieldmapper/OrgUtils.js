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

if(!dojo._hasResource["fieldmapper.OrgUtils"]){

	dojo._hasResource["fieldmapper.OrgUtils"] = true;
	dojo.provide("fieldmapper.OrgUtils");
	dojo.require("fieldmapper.Fieldmapper");
	dojo.require("fieldmapper.hash");
	dojo.require("fieldmapper.OrgTree", true);
	dojo.require("fieldmapper.OrgLasso", true);

	fieldmapper.aou.slim_ok = true;
	fieldmapper.aou.globalOrgTree = {};
	fieldmapper.aou.OrgCache = {};
	fieldmapper.aou.OrgCacheSN = {};
	fieldmapper.aout.OrgTypeCache = {};

	fieldmapper.aout.LoadOrgTypes = function () {
		for (var i in fieldmapper.aout.OrgTypeCache) {
			return;
		}

		var types = fieldmapper.standardRequest(['open-ils.actor','open-ils.actor.org_types.retrieve']);

		for (var i in types) {
			fieldmapper.aout.OrgTypeCache[types[i].id()] = {
				loaded : true,
				type : types[i]
			};
		}
	}

	fieldmapper.aou.LoadOrg = function (id, slim_ok) {
		if (slim_ok == null) slim_ok = fieldmapper.aou.slim_ok;
		var slim_o = fieldmapper.aou.OrgCache[id];

		if (slim_o && (slim_ok || slim_o.loaded))
			return fieldmapper.aou.OrgCache[id].org;

		var o = fieldmapper.standardRequest(['open-ils.actor','open-ils.actor.org_unit.retrieve'],[null,id]);
		o.children = fieldmapper.aou.OrgCache[o.id()].children;
		fieldmapper.aou.OrgCache[o.id()] = { loaded : true, org : o };
		return o;
	}
	fieldmapper.aou.findOrgUnit = fieldmapper.aou.LoadOrg;

	if (window._l) {
		for (var i in _l) {
			fieldmapper.aou.OrgCache[_l[i][0]] = {
				loaded: false,
				org : new fieldmapper.aou().fromHash({
					id : _l[i][0],
					ou_type : _l[i][1],
					parent_ou : _l[i][2],
					name : _l[i][3],
					opac_visible : _l[i][4],
					shortname : _l[i][5]
				})
			};

		}

		for (var i in fieldmapper.aou.OrgCache) {
			var x = fieldmapper.aou.OrgCache[i].org;
			if (x.parent_ou() == null || x.parent_ou() == '') {
				fieldmapper.aou.globalOrgTree = x;
				continue;
			}

			var par = fieldmapper.aou.findOrgUnit(x.parent_ou(),true);
			if (!par.children()) par.children([]);
			par.children().push(x);
			fieldmapper.aou.OrgCache[x.id()].treePtr = x;
		}

		for (var i in globalOrgTypes) {
			fieldmapper.aout.OrgTypeCache[globalOrgTypes[i].id()] = {
				loaded : true,
				type : globalOrgTypes[i]
			};
		}
	}


   /* ---------------------------------------------------------------------- */

	fieldmapper.aou.prototype.fetchOrgSettingDefault = function (name) {
		return this.standardRequest( fieldmapper.OpenSRF.methods.FETCH_ORG_SETTING, [this.id(), name] ); 
	}

	fieldmapper.aou.prototype.fetchOrgSettingBatch = function (nameList) {
		return this.standardRequest( fieldmapper.OpenSRF.methods.FETCH_ORG_SETTING_BATCH, [this.id(), nameList] ); 
	}

	fieldmapper.aou.fetchOrgSettingDefault = function (orgId, name) {
		return fieldmapper.standardRequest( fieldmapper.OpenSRF.methods.FETCH_ORG_SETTING, [orgId, name] ); 
	}

	fieldmapper.aou.fetchOrgSettingBatch = function (orgId, nameList) {
		return fieldmapper.standardRequest( fieldmapper.OpenSRF.methods.FETCH_ORG_SETTING_BATCH, [orgId, nameList] ); 
	}

	fieldmapper.aout.findOrgType = function (id) {
		fieldmapper.aout.LoadOrgTypes();
		return fieldmapper.aout.OrgTypeCache[id].type;
	}

	fieldmapper.aou.prototype.findOrgDepth = function (id) {
		if (!id) id = this.id;
		if (!id) return null;

		var org = fieldmapper.aou.findOrgUnit(id);
		return fieldmapper.aout.findOrgType(
			fieldmapper.aou.findOrgUnit(id).ou_type()
		).depth();
	}
	fieldmapper.aou.findOrgDepth = fieldmapper.aou.prototype.findOrgDepth;

	fieldmapper.aout.findOrgTypeFromDepth = function (depth) {
		if( depth == null ) return null;
		fieldmapper.aout.LoadOrgTypes();
		for( var i in fieldmapper.aout.OrgTypeCache ) {
			var t = fieldmapper.aout.OrgTypeCache[i].type;
			if( t.depth() == depth ) return t;
		}
		return null;
	}

	fieldmapper.aou.findOrgUnitSN = function (sn, slim_ok) {
		if (slim_ok == null) slim_ok = fieldmapper.aou.slim_ok;
		var org = fieldmapper.aou.OrgCacheSN[sn];
		if (!org) {
			for (var i in fieldmapper.aou.OrgCache) {
				var o = fieldmapper.aou.OrgCache[i];
				if (o.org.shortname() == sn) {
					fieldmapper.aou.OrgCacheSN[o.org.shortname()] = o;
					org = o;
				}
			}

			if (!slim_ok && !fieldmapper.aou.OrgCache[org.id()].loaded) {
				org = fieldmapper.standardRequest(fieldmapper.OpenSRF.methods.FETCH_ORG_BY_SHORTNAME, sn);

				org.children = fieldmapper.aou.OrgCache[org.id()].children;
				fieldmapper.aou.OrgCache[org.id()] = { loaded : true, org : org };
				fieldmapper.aou.OrgCacheSN[org.shortname()] = { loaded : true, org : org };
			}

		}

		return org;
	}

	fieldmapper.aou.prototype.orgNodeTrail = function (node) {
		if (!node) node = this;
		if (!node) return [];

		var na = [];

		while( node ) {
			na.push(node);
			node = null;
			if (node.parent_ou())
				node = fieldmapper.aou.findOrgUnit(node.parent_ou());
		}

		return na.reverse();
	}
	fieldmapper.aou.orgNodeTrail = fieldmapper.aou.prototype.orgNodeTrail;

	fieldmapper.aou.prototype.orgIsMine = function (me, org) {
		if (this._isfieldmapper) {
			org = me;
			me = this;
		}

		if(!me || !org) return false;

		if(me.id() == org.id()) return true;

		for( var i in me.children() ) {
			if(me.children()[i].orgIsMine(org)) return true;
		}
		return false;
	}

    /** Given an org id, returns an array of org units including
     * the org for the ID provided and all descendant orgs */
    fieldmapper.aou.descendantNodeList = function(orgId) {
        var list = [];
        function addNode(node) {
            if(!node) return;
            list.push(node);
            var children = node.children();
            if(children) {
                for(var i = 0; i < children.length; i++) 
                    addNode(children[i]);
            }
        }
        addNode(fieldmapper.aou.findOrgUnit(orgId));
        return list;
    }

	dojo.addOnUnload( function () {
		for (var i in fieldmapper.aou.OrgCache) {
			x=fieldmapper.aou.OrgCache[i].treePtr;
			if (!x) continue;

			x.children(null);
			x.parent_ou(null);
			fieldmapper.aou.OrgCache[i]=null;
		}
		fieldmapper.aou.globalOrgTree = null;
		fieldmapper.aou.OrgCache = null;
		fieldmapper.aou.OrgCacheSN = null;
		fieldmapper.aout.OrgTypeCache = null;
	});
}



