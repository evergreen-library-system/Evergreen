dump('entering util/sound.js\n');

if (typeof util == 'undefined') util = {};
util.sound = function () {

    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        var SOUNDContractID = "@mozilla.org/sound;1";
        var SOUNDIID        = Components.interfaces.nsISound;
        this.SOUND          = Components.classes[SOUNDContractID].createInstance(SOUNDIID);
        this.SOUND.init(); // not necessary, but helps avoid delays?

    } catch(E) {
        dump('util.sound constructor: ' + E + '\n');
    }

    return this;
};

util.sound.prototype = {

    'xp_url_init' : function (aURL) {
        try {
            netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
            var URLContractID   = "@mozilla.org/network/standard-url;1";
            var URLIID          = Components.classes[URLContractID].createInstance( );
            var URL             = URLIID.QueryInterface(Components.interfaces.nsIURL);
            if (aURL) {
                URL.spec = aURL;
            }
            return URL;
        } catch(E) {
            alert('xp_url_init(): ' + E);
        }
    },

    'play_url' : function(url) {

        if (!url) { return; /* sound of silence */ }

        var obj = this;
        try {
            netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
            var url2 = obj.xp_url_init( data.server + url );
            dump('SOUND: file = ' + url + '\n');
            if (typeof data.no_sound == 'undefined' || data.no_sound == false || data.no_sound == 'false') obj.SOUND.play( url2 );
        } catch(E) {
            try { if (data.no_sound == 'undefined' || data.no_sound == false || data.no_sound == 'false') obj.SOUND.beep(); } catch(F) { 
                dump('beep(): ' + F + '\n');
            }
            dump('play_url(): ' + E + '\n');
        }
    },

    'event' : function event(evt) {
        var key = 'AUDIO_' + arguments.callee.name + '_' + evt.textcode;
        dump('SOUND: key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'good' : function good(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND: key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'bad' : function bad(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND: key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'horrible' : function horrible(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND: key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'circ_good' : function circ_good(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND: key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'circ_bad' : function circ_bad(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND: key = ' + key + '\n');
        this.play_url( urls[key] );
    }
}

dump('exiting util/sound.js\n');
