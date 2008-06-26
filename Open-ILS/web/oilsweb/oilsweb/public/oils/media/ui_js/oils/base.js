function loadUser(username, password) {
    dojo.require('dojo.cookie');
    dojo.require('openils.CGI');
    dojo.require("openils.User");

    openils.User.authcookie = 'ses';
    openils.User.authtoken = dojo.cookie('ses') || new openils.CGI().param('ses');
    // cache the user object as a cookie?
    //openils.User.user = JSON2js(dojo.cookie('user'));

    if(!username) return;

    dojo.require('openils.Event');

    function dologin() {
        openils.User.authtoken = null;
        user = new openils.User();
        user.login({
            login_type:'staff', 
            username:username, 
            passwd:password, 
            login:true
        });
        user.getBySession();
        openils.User.authtoken = user.authtoken;
        openils.User.user = user.user;
        //dojo.cookie('user', js2JSON(openils.User.user),{path:'/'});
    }

    if(!openils.User.user) {
        if(openils.User.authtoken) {
            user = new openils.User();
            openils.User.user = user.user;
            if(openils.Event.parse(user.user)) // session timed out
                dologin();
        } else {
            dologin();
        }
    }
}

