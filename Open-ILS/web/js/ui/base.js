dojo.require('dijit.Dialog');
dojo.require('dojo.cookie');
dojo.require('fieldmapper.AutoIDL');  // make conditional.  TT variable sets JS var to enable/disable?
dojo.require('openils.User');
dojo.require('openils.CGI');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.XUL');

var cgi = new openils.CGI();

function oilsSetupUser() {
    var authtoken = cgi.param('ses') || dojo.cookie('ses');
    var workstation = cgi.param('ws') || dojo.cookie('ws');
    var user;
    var ses_user;

    openils.User.user = null;
    openils.User.authtoken = null;
    openils.User.workstation = null;

    if(openils.XUL.isXUL()) {
		stash = openils.XUL.getStash();
		authtoken = stash.session.key
        ses_user = stash.list.au[0];
	}

    if(authtoken) {
        user = new openils.User();
        delete user.sessionCache[authtoken];
        user.authtoken = authtoken;
        if(ses_user) {
            user.user = ses_user;
            user.sessionCache[authtoken] = ses_user;
        }
        user.user = user.getBySession();
    }

    if(!authtoken || openils.Event.parse(user.user)) {

        authtoken = oilsLoginFromCookies();

        if(!authtoken) {

            dojo.cookie('ses', null, {expires:-1, path:'/'}); // remove the cookie

            dojo.addOnLoad(function(){
                if(openils.XUL.isXUL()) {
                    // let XUL handle the login dialog
                    dump('getNewSession in base.js\n');
                    openils.XUL.getNewSession( function() { location.href = location.href } );
                } else {
                    // in web-only mode, use the dojo login dialog
                    oilsLoginDialog.show(); 
                    var func = function(){ oilsDoLogin(); };
                    openils.Util.registerEnterHandler(dojo.byId('oils-login-username'), func);
                    openils.Util.registerEnterHandler(dojo.byId('oils-login-password'), func);
                    dojo.byId('oils-login-workstation').innerHTML = workstation || '';
                }
            });
            return null;
        }
    }

    dojo.cookie('ses', authtoken, {path:'/', 'secure' : true});
    openils.User.authtoken = authtoken;
    openils.User.workstation = workstation;
    return authtoken;
}

// pulls username / password and optional workstation from cgi params or cookies
function oilsLoginFromCookies() {

    var username = cgi.param('username') || dojo.cookie('username');
    var password = cgi.param('password') || dojo.cookie('password');
    var workstation = cgi.param('ws') || dojo.cookie('ws');

    if(username && password) {

        var user = new openils.User();
        var args = {
            username : username,
            passwd : password,
            type : 'staff'
        };

        if(workstation) 
            args.workstation = workstation;

        if(user.login(args)) {
            // fetches the login session and sets the global vars
            user = new openils.User({authtoken : user.authtoken});
            return (user && !openils.Event.parse(user.user)) ? user.authtoken : null;
        } 
    }

    return null;
}

function oilsDoLogin() {
    openils.Util.hide('oils-login-failed');
    var workstation = cgi.param('ws') || dojo.cookie('ws');
    var user = new openils.User();
    var args = {
        username: dojo.byId('oils-login-username').value,
        passwd: dojo.byId('oils-login-password').value,
        type: 'staff', // hardcode for now
    };
    if(workstation) 
        args.workstation = workstation;

    if(user.login(args)) {
        dojo.cookie('ses', user.authtoken, {path : '/'});
        location.href = location.href;
    } else {
        openils.Util.show('oils-login-failed');
    }

    return false;
}

oilsSetupUser();

