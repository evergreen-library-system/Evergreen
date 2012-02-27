dump('entering auth/session.js\n');
// vim:sw=4:ts=4:et:

if (typeof auth == 'undefined') auth = {};
auth.session = function (view,login_type) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.network'); this.network = new util.network();
    this.view = view;
    this.login_type = login_type || 'staff';

    return this;
};

auth.session.prototype = {

    'init' : function () {

        var obj = this;

        /* This request is done manually in a try block to allow it to fail
         * silently if auth_proxy is not even running.  TODO: Move this check
         * to a module which should be always running, perhaps 'auth'.
         */
        var auth_proxy_enabled = false;
        try {
            var request = new RemoteRequest( api.AUTH_PROXY_ENABLED.app, api.AUTH_PROXY_ENABLED.method );
            request.send(true);
            request.setSecure(true);
            if (request.getResultObject() == 1) {
                auth_proxy_enabled = true;
            }
        } catch(E) {
        }

        try {
            if (!auth_proxy_enabled) {
                var init = this.network.request(
                    api.AUTH_INIT.app,
                    api.AUTH_INIT.method,
                    [ this.view.name_prompt.value ]
                );
            }

            if (init || auth_proxy_enabled) {
                if (xulG._data) {
                    /* quick kludge; we were re-using a poisoned OpenILS.data
                     * (from ws_info.xul?) where js2JSON (and maybe other
                     * stuff) does not exist
                     */
                    delete xulG._data;
                }

                JSAN.use('OpenILS.data');
                var data = new OpenILS.data();
                data.stash_retrieve();

                var params = { 
                    'username' : this.view.name_prompt.value,
                    'type' : 'temp',
                    'agent' : 'staffclient'
                };

                if (data.ws_info[ this.view.server_prompt.value ]) {
                    params.type = this.login_type;
                    params.workstation = data.ws_info[ this.view.server_prompt.value ].name;
                    data.ws_name = params.workstation; data.stash('ws_name');
                }

                var robj;
                if (init) {
                    params['password'] = hex_md5(
                        init +
                        hex_md5(
                            this.view.password_prompt.value
                        )
                    );
                    robj = this.network.simple_request( 'AUTH_COMPLETE', [ params ]);
                } else if (auth_proxy_enabled) { // safety double-check
                    params['password'] = this.view.password_prompt.value;
                    robj = this.network.simple_request( 'AUTH_PROXY_LOGIN', [ params ] );
                }

                switch (Number(robj.ilsevent)) {
                    case 0:
                        this.key = robj.payload.authtoken;
                        this.authtime = robj.payload.authtime;
                    break;
                    case 1520 /* WORKSTATION_NOT_FOUND */:
                        alert(document.getElementById('authStrings').getFormattedString('staff.auth.session.unregistered', [params.workstation]));
                        delete(params.workstation);
                        delete(data.ws_info[ this.view.server_prompt.value ]);
                        data.stash('ws_info');
                        data.ws_name = null; data.stash('ws_name');
                        params.type = 'temp';
                        // We need to get a new seed
                        init = this.network.request(
                            api.AUTH_INIT.app,
                            api.AUTH_INIT.method,
                            [ this.view.name_prompt.value ]
                        );
                        if(init) {
                            params.password = hex_md5(init + hex_md5( this.view.password_prompt.value ));
                        }
                        robj = this.network.simple_request('AUTH_COMPLETE',[ params ]);
                        if (robj.ilsevent == 0) {
                            this.key = robj.payload.authtoken;
                            this.authtime = robj.payload.authtime;
                        } else {
                            //this.error.standard_unexpected_error_alert('auth.session.init',robj);
                            throw(robj);
                        }
                    break;
                    default:
                    //obj.error.standard_unexpected_error_alert('auth.session.init',robj);
                    throw(robj);
                    break;
                }

                this.error.sdump('D_AUTH','auth.session.key = ' + this.key + '\n');

                if (typeof this.on_init == 'function') {
                    this.error.sdump('D_AUTH','auth.session.on_init()\n');
                    this.on_init();
                }

            } else {

                var error = document.getElementById('authStrings').getString('staff.auth.session.init_false') + '\n';
                this.error.sdump('D_ERROR',error);
                throw(error);
            }

        } catch(E) {
            alert(document.getElementById('authStrings').getString('staff.auth.session.login_failed'));
            //obj.error.standard_unexpected_error_alert('Error on auth.session.init()',E); 

            if (typeof this.on_init_error == 'function') {
                this.error.sdump('D_AUTH','auth.session.on_init_error()\n');
                this.on_init_error(E);
            }
            if (typeof this.on_error == 'function') {
                this.error.sdump('D_AUTH','auth.session.on_error()\n');
                this.on_error();
            }

            //throw(E);
            /* This was for testing
            if (typeof this.on_init == 'function') {
                this.error.sdump('D_AUTH','auth.session.on_init() despite error\n');
                this.on_init();
            }
            */
        }
    },

    'close' : function () { 
        var obj = this;
        obj.error.sdump('D_AUTH','auth.session.close()\n'); 
        try {
            // Remove *our* cookie(s), but leave any from elsewhere alone.
            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
            var host = data.server_unadorned;
            host = host.toLowerCase();
            var cookieManager = Components.classes["@mozilla.org/cookiemanager;1"]
                .getService(Components.interfaces.nsICookieManager);
            var iter = cookieManager.enumerator;
            while (iter.hasMoreElements()) {
                var cookie = iter.getNext();
                if (cookie instanceof Components.interfaces.nsICookie) {
                    var temphost = cookie.host.toLowerCase();
                    if(temphost == host || temphost == '.' + host) {
                        cookieManager.remove(cookie.host, cookie.name, cookie.path, cookie.blocked);
                    }
                }
            }
        } catch(E) {
            dump('Error in auth/session.js, close(): ' + E + '\n');
        }
        if (obj.key) obj.network.request(
            api.AUTH_DELETE.app,
            api.AUTH_DELETE.method,
            [ obj.key ],
            function(req) {}
        );
        obj.key = null;
        if (typeof obj.on_close == 'function') {
            obj.error.sdump('D_AUTH','auth.session.on_close()\n');
            obj.on_close();
        }
    }

}

dump('exiting auth/session.js\n');
