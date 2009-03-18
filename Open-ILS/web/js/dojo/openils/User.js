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


if(!dojo._hasResource["openils.User"]) {

    dojo._hasResource["openils.User"] = true;
    dojo.provide("openils.User");
    dojo.require("DojoSRF");
    dojo.require('openils.Event');
    dojo.require('fieldmapper.Fieldmapper');
    dojo.require('fieldmapper.OrgUtils');
    dojo.require('openils.Util');

    dojo.declare('openils.User', null, {

        user : null,
        username : null,
        passwd : null,
        login_type : 'opac',
        location : null,
        authtoken : null,
        authtime : null,
        workstation : null,
        permOrgCache : {},
        sessionCache : {},
    
        constructor : function ( kwargs ) {
            kwargs = kwargs || {};
            this.id = kwargs.id;
            this.user = kwargs.user;
            this.passwd = kwargs.passwd;
            this.authtoken = kwargs.authtoken || openils.User.authtoken;
            this.authtime = kwargs.authtime || openils.User.authtime;
            this.login_type = kwargs.login_type;
            this.location = kwargs.location;
            this.authcookie = kwargs.authcookie || openils.User.authcookie;
            this.permOrgStoreCache = {}; /* permName => permOrgUnitStore map */

            if (this.id && this.authtoken) this.user = this.getById( this.id );
            else if (this.authtoken) this.getBySession();
            else if (kwargs.login) this.login();

            var id = this.id || (this.user && this.user.id) ? this.user.id() : null;
            if(id && !this.permOrgCache[id])
                this.permOrgCache[id] = {};
        },

        getBySession : function(onComplete) {
            var _u = this;
            var req = ['open-ils.auth', 'open-ils.auth.session.retrieve'];
            var params = [_u.authtoken];

            if(this.sessionCache[this.authtoken]) {
                this.user = this.sessionCache[this.authtoken];
				if (!openils.User.user) 
                    openils.User.user = this.user;
                return this.user;
            }

            if(onComplete) {
                fieldmapper.standardRequest(
                    req, {   
                        async: true,
                        params: params,
                        oncomplete : function(r) {
                            var user = r.recv().content();
                            _u.user = user;
                            _u.sessionCache[_u.authtoken] = user;
					        if (!openils.User.user) openils.User.user = _u.user;
                            if(onComplete)
                                onComplete(user);
                        }
                    }
                );
            } else {
                _u.user = fieldmapper.standardRequest(req, params);
				if (!openils.User.user) openils.User.user = _u.user;
                _u.sessionCache[_u.authtoken] = _u.user;
                return _u.user;
            }
        },
    
        getById : function(id, onComplete) {
            var req = OpenSRF.CachedClientSession('open-ils.actor').request('open-ils.actor.user.retrieve', this.authtoken, id);
            if(onComplete) {
                req.oncomplete = function(r) {
                    var user = r.recv().content();
                    onComplete(user);
                }
                req.send();
            } else {
                req.timeout = 10;
                req.send();
                return req.recv().content();
            }
        },
    
    
        /**
         * Logs in, sets the authtoken/authtime vars, and fetches the logged in user
         */
        login_async : function(args, onComplete) {
            var _u = this;

            if (!args) args = {};
            if (!args.username) args.username = _u.username;
            if (!args.passwd) args.passwd = _u.passwd;
            if (!args.type) args.type = _u.login_type;
            if (!args.location) args.location = _u.location;

            var initReq = OpenSRF.CachedClientSession('open-ils.auth').request('open-ils.auth.authenticate.init', args.username);
    
            initReq.oncomplete = function(r) {
                var seed = r.recv().content(); 
                var loginInfo = {
                    username : args.username,
                    password : hex_md5(seed + hex_md5(args.passwd)), 
                    type : args.type,
                    org : args.location,
                    workstation : args.workstation
                };
    
                var authReq = OpenSRF.CachedClientSession('open-ils.auth').request('open-ils.auth.authenticate.complete', loginInfo);
                authReq.oncomplete = function(rr) {
                    var data = rr.recv().content();
                    _u.authtoken = data.payload.authtoken;
					if (!openils.User.authtoken) openils.User.authtoken = _u.authtoken;
                    _u.authtime = data.payload.authtime;
					if (!openils.User.authtime) openils.User.authtime = _u.authtime;
                    _u.getBySession(onComplete);
                    if(_u.authcookie) {
                        dojo.require('dojo.cookie');
                        dojo.cookie(_u.authcookie, _u.authtoken, {path:'/'});
                    }
                }
                authReq.send();
            }
    
            initReq.send();
        },

        login : function(args) {
            var _u = this;
            if (!args) args = {};
            if (!args.username) args.username = _u.username;
            if (!args.passwd) args.passwd = _u.passwd;
            if (!args.type) args.type = _u.login_type;
            if (!args.location) args.location = _u.location;

            var seed = fieldmapper.standardRequest(
                ['open-ils.auth', 'open-ils.auth.authenticate.init'],
                [args.username]
            );

            var loginInfo = {
                username : args.username,
                password : hex_md5(seed + hex_md5(args.passwd)), 
                type : args.type,
                org : args.location,
                workstation : args.workstation,
            };

            var data = fieldmapper.standardRequest(
                ['open-ils.auth', 'open-ils.auth.authenticate.complete'],
                [loginInfo]
            );

            _u.authtoken = data.payload.authtoken;
            if (!openils.User.authtoken) openils.User.authtoken = _u.authtoken;
            _u.authtime = data.payload.authtime;
            if (!openils.User.authtime) openils.User.authtime = _u.authtime;

            if(_u.authcookie) {
                dojo.require('dojo.cookie');
                dojo.cookie(_u.authcookie, _u.authtoken, {path:'/'});
            }
        },

    
        /**
         * Returns a list of the "highest" org units where the user has the given permission(s).
         * @param permList A single permission or list of permissions
         * @param includeDescendents If true, return a list of 'highest' orgs plus descendents
         * @idlist If true, return a list of IDs instead of org unit objects
         */
        getPermOrgList : function(permList, onload, includeDescendents, idlist) {
            if(typeof permList == 'string') permList = [permList];

            var self = this;
            var oncomplete = function(r) {
                var permMap = {};
                if(r) permMap = openils.Util.readResponse(r);
                var orgList = [];
                for(var i = 0; i < permList.length; i++) {
                    var perm = permList[i];
                    var permOrgList = permMap[perm] || self.permOrgCache[self.user.id()][perm];
                    self.permOrgCache[self.user.id()][perm] = permOrgList;
                    for(var i in permOrgList) {
                        if(includeDescendents) {
                            orgList = orgList.concat(
                                fieldmapper.aou.descendantNodeList(permOrgList[i]));
                        } else {
                            orgList = orgList.concat(fieldmapper.aou.findOrgUnit(permOrgList[i]));
                        }
                    }
                }

                // remove duplicates
                var trimmed = [];
                for(var idx in orgList) {
                    var val = (idlist) ? orgList[idx].id() : orgList[idx];
                    if(trimmed.indexOf(val) < 0)
                        trimmed.push(val);
                }
                onload(trimmed);
            };

            var fetchList = [];
            for(var i = 0; i < permList.length; i++) {
                if(!self.permOrgCache[self.user.id()][permList[i]])
                    fetchList.push(permList[i]);
            }

            if(fetchList.length == 0) 
                return oncomplete();

            fieldmapper.standardRequest(
                ['open-ils.actor', 'open-ils.actor.user.has_work_perm_at.batch'],
                {   async: true,
                    params: [this.authtoken, fetchList],
                    oncomplete: oncomplete
                }
            );
        },

    
        /**
         * Sets the store for an existing openils.widget.OrgUnitFilteringSelect 
         * using the orgs where the user has the requested permission.
         * @param perm The permission to check
         * @param selector The pre-created dijit.form.FilteringSelect object.  
         */
        buildPermOrgSelector : function(perm, selector, selectedOrg, onload) {
            var _u = this;
    
            dojo.require('dojo.data.ItemFileReadStore');

            function hookupStore(store) {
                selector.store = store;
                selector.startup();
                if(selectedOrg != null)
                    selector.setValue(selectedOrg);
                else
                    selector.setValue(_u.user.ws_ou());
                if(onload) onload();
            }

            function buildTreePicker(orgList) {
                var store = new dojo.data.ItemFileReadStore({data:aou.toStoreData(orgList)});
                hookupStore(store);
                _u.permOrgStoreCache[perm] = store;
            }
    
	        if (_u.permOrgStoreCache[perm])
		        hookupStore(_u.permOrgStoreCache[perm]);
	        else
                _u.getPermOrgList(perm, buildTreePicker, true);
        },
    });

	openils.User.user = null;
	openils.User.authtoken = null;
	openils.User.authtime = null;
    openils.User.authcookie = null;
}


