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

    dojo.declare('openils.User', null, {});

    openils.User.user = null;
    openils.User.authtoken = null;
    openils.User.authtime = null;

    var ses = new OpenSRF.ClientSession('open-ils.auth');

    openils.User.getBySession = function(onComplete) {
        var req = ses.request('open-ils.auth.session.retrieve', openils.User.authtoken);
        req.oncomplete = function(r) {
            var user = r.recv().content();
            openils.User.user = user;
            if(onComplete)
                onComplete(user);
        }
        req.send();
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
}


