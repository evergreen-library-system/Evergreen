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
    dojo.require('openils.Event');
    dojo.require('fieldmapper.Fieldmapper');

    dojo.declare('openils.User', null, {});

    openils.User.user = null;
    openils.User.authtoken = null;
    openils.User.authtime = null;

    var ses = new OpenSRF.ClientSession('open-ils.auth');

    openils.User.getBySession = function(onComplete) {
        var req = ses.request('open-ils.auth.session.retrieve', openils.User.authtoken);
        if(onComplete) {
            req.oncomplete = function(r) {
                var user = r.recv().content();
                openils.User.user = user;
                if(onComplete)
                    onComplete(user);
            }
            req.send();
        } else {
            req.timeout = 10;
            req.send();
            return openils.User.user = req.recv().content();
        }
    }

    openils.User.getById = function(id, onComplete) {
        var ases = new OpenSRF.ClientSession('open-ils.actor');
        var req = ases.request('open-ils.actor.user.retrieve', openils.User.authtoken, id);
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
    }


    /**
     * Logs in, sets the authtoken/authtime vars, and fetches the logged in user
     */
    openils.User.login = function(args, onComplete) {
        var initReq = ses.request('open-ils.auth.authenticate.init', args.username);

        initReq.oncomplete = function(r) {
            var seed = r.recv().content(); 
            alert(seed);
            var loginInfo = {
                password : hex_md5(seed + hex_md5(args.passwd)), 
                type : args.type || 'opac',
                org : args.location,
            };

            var authReq = ses.request('open-ils.auth.authenticate.complete', loginInfo);
            authReq.oncomplete = function(rr) {
                var data = rr.recv().content();
                openils.User.authtoken = data.payload.authtoken;
                openils.User.authtime = data.payload.authtime;
                openils.User.getBySession(onComplete);
            }
            authReq.send();
        }

        initReq.send();
    }

    /**
     * Returns a list of the "highest" org units where the user
     * has the given permission.
     */
    openils.User.getPermOrgList = function(perm, onload) {

        var ases = new OpenSRF.ClientSession('open-ils.actor');
        var req = ases.request(
            'open-ils.actor.user.work_perm.highest_org_set',
            openils.User.authtoken, perm);

        req.oncomplete = function(r) {
            org_list = r.recv().content();
            onload(org_list);
        }

        req.send();
    }

    /**
     * Builds a dijit.Tree using the orgs where the user has the requested permission
     * @param perm The permission to check
     * @param domId The DOM node where the tree widget should live
     * @param onClick If defined, this will be connected to the tree widget for
     * onClick events
     */
    openils.User.buildPermOrgTreePicker = function(perm, domId, onClick) {

        function buildTreePicker(r) {
            var orgList = r.recv().content();
            var store = new dojo.data.ItemFileReadStore({data:aou.toStoreData(orgList)});
            var model = new dijit.tree.ForestStoreModel({
                store: store,
                query: {_top:'true'},
                childrenAttrs: ["children"],
                rootLabel : "Location" /* XXX i18n */
            });

            var tree = new dijit.Tree({model : model}, dojo.byId(domId));
            if(onClick)
                dojo.connect(tree, 'onClick', onClick);
            tree.startup()
        }

        fieldmapper.standardRequest(
            ['open-ils.actor', 'open-ils.actor.user.work_perm.org_unit_list'],
            {
                params: [openils.User.authtoken, 'ADMIN_FUNDING_SOURCE'],
                oncomplete: buildTreePicker,
                async: true
            }
        )
    }
}


