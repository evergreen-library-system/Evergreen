dojo.require('dijit.Dialog');
dojo.require('fieldmapper.dojoData');
dojo.require('openils.User');
dojo.require('dojo.cookie');
dojo.require('openils.CGI');
dojo.require('openils.Event');

function oilsSetupUser() {
    var authtoken = new openils.CGI().param('ses') || dojo.cookie('ses');
    var user;
    if(authtoken) user = new openils.User({authtoken:authtoken});
    if(!authtoken || openils.Event.parse(user.user)) {
        dojo.cookie('ses', openils.User.authtoken, {expires:-1, path:'/'});
        openils.User.authtoken = null;
        dojo.addOnLoad(function(){oilsLoginDialog.show();});
        return;
    }
    dojo.cookie('ses', authtoken, {path : oilsCookieBase});
    openils.User.authtoken = authtoken;
}

function oilsDoLogin() {
    var user = new openils.User();
    user.login({
        username: dojo.byId('oils-login-username').value,
        passwd: dojo.byId('oils-login-password').value,
        type: 'staff' // hardcode for now
    });
    dojo.cookie('ses', user.authtoken, {path : oilsCookieBase});
    return true;
}

oilsSetupUser();

