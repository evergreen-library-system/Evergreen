dump('entering util/window.js\n');

if (typeof util == 'undefined') util = {};
util.window = function () {
    JSAN.use('util.error'); this.error = new util.error(); this.win = window;
    return this;
};

util.window.prototype = {
    
    // list of open window references, used for debugging in shell
    'win_list' : [],    

    // list of Top Level menu interface window references
    'appshell_list' : [],    

    // list of documents for debugging.  BROKEN
    'doc_list' : [],    

    // This number gets put into the title bar for Top Level menu interface windows
    'appshell_name_increment' : function() {
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
        if (typeof data.appshell_name_increment == 'undefined') {
            data.appshell_name_increment = 1;
        } else {
            data.appshell_name_increment++;
        }
        data.stash('appshell_name_increment');
        return data.appshell_name_increment;
    },

    // From: Bryan White on netscape.public.mozilla.xpfe, Oct 13, 2004
    // Message-ID: <ckjh7a$18q1@ripley.netscape.com>
    // Modified by Jason for Evergreen
    'SafeWindowOpenDialog' : function (url,title,features) {
        var w;

        const CI = Components.interfaces;
        const PB = Components.classes["@mozilla.org/preferences-service;1"].getService(CI.nsIPrefBranch);

        var blocked = false;
        try {
            // pref 'dom.disable_open_during_load' is the main popup blocker preference
            blocked = PB.getBoolPref("dom.disable_open_during_load");
            if(blocked) PB.setBoolPref("dom.disable_open_during_load",false);
            w = this.win.openDialog.apply(this.win,arguments);
        } catch(E) {
            this.error.sdump('D_ERROR','window.SafeWindowOpenDialog: ' + E + '\n');
            throw(E);
        }
        if(blocked) PB.setBoolPref("dom.disable_open_during_load",true);

        return w;
    },

    // This has basically become a compatibility wrapper for openDialog.
    'open' : function(url,title,features,my_xulG) {
        var key;
        if (!features) features = 'chrome,dialog=no';
        if (!features.match(/dialog/)) features = 'dialog=no,' + features; // window.open doesn't do dialog by default
        if (!features.match(/chrome/)) features = 'chrome=no,' + features; // And window.open doesn't assume chrome by default
        var outArgs = Array.prototype.slice.call(arguments);
        outArgs[1] = title;
        outArgs[2] = features;
        return this.openDialog.apply(this, outArgs); // Pass to openDialog
    },

    'openDialog' : function(url,title,features,my_xulG) {
        var key;
        if (!title) title = '_blank';
        if (!features) features = 'chrome'; // Note that this is a default for openDialog anyway
        var outArgs = Array.prototype.slice.call(arguments);
        outArgs[1] = title;
        outArgs[2] = features;
        this.error.sdump('D_WIN', 'opening ' + url + ', ' + title + ', ' + features + ' from ' + this.win + '\n');
        var data;
        var w = this.SafeWindowOpenDialog.apply(this, outArgs);
        if (features.match(/modal/) && my_xulG) { 
            return my_xulG;
        } else {
            if (my_xulG) {
                if (get_contentWindow(w)) {
                    get_contentWindow(w).xulG = my_xulG;
                } else {
                    w.xulG = my_xulG;
                }
            }
        }
        /*
        setTimeout( 
            function() { 
                try { w.title = title; } catch(E) { dump('**'+E+'\n'); }
                try { w.document.title = title; } catch(E) { dump('**'+E+'\n'); }
            }, 0 
        );
        */
        return w;
    }
}

dump('exiting util/window.js\n');
