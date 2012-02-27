dump('entering util/sound.js\n');

if (typeof util == 'undefined') util = {};
util.sound = function (params) {

    try {

        if (!params) { params = {}; }

        this.sig = (new Date()).getMinutes() + ':' + (new Date()).getSeconds() + '.' + (new Date()).getMilliseconds()/1000;
        if (params.sig) { this.sig += ' ' + params.sig; }

        /* We're going to turn this guy into a singleton, at least for a given window, and look for it in xulG */
        if (! window.xulG) { window.xulG = {}; }
        if (window.xulG._sound && !params.reuse_queue_from_this_snd_obj) { 
            dump('SOUND('+this.sig+'): reusing sound from ' + window.xulG._sound.origin + '('+xulG._sound.sig+') for ' + location.pathname + '\n');
            return window.xulG._sound; 
        } else {
            dump('SOUND('+this.sig+'): instantiating new sound for ' + location.pathname + '\n');
        }

        /* So we can queue up sounds and put a pause between them instead of having them trample over each other */
        /* Limitation: interval only gets set once for a singleton */
        if (params.interval || params.reuse_queue_from_this_snd_obj) {
            this._queue = true;
            if (params.reuse_queue_from_this_snd_obj) {
                this._funcs = params.reuse_queue_from_this_snd_obj._funcs || [];
            } else {
                this._funcs = [];
            }
            JSAN.use('util.exec');
            this._exec = new util.exec();
            var delay = params.interval;
            if (!delay) { delay = _sound_delay_interval; /* define this in server/skin/custom.js */ }
            if (!delay) { delay = 2000; }
            var intervalId = this._exec.timer( this._funcs, delay );
            dump('SOUND('+this.sig+'): starting timer with intervalId = ' + intervalId + '\n');
        }

        var SOUNDContractID = "@mozilla.org/sound;1";
        var SOUNDIID        = Components.interfaces.nsISound;
        this.SOUND          = Components.classes[SOUNDContractID].createInstance(SOUNDIID);
        this.SOUND.init(); // not necessary, but helps avoid delays?

        this.origin = location.pathname;

        window.xulG._sound = this;
        return this;

    } catch(E) {
        dump('error in util.sound constructor: ' + E + '\n');
        return this;
    }
};

util.sound.prototype = {

    'xp_url_init' : function (aURL) {
        try {
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
            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
            var url2 = obj.xp_url_init( data.server + url );
            if (typeof data.no_sound == 'undefined' || data.no_sound == false || data.no_sound == 'false') {

                if (obj._queue) {
                    dump('SOUND('+obj.sig+'): queueing file = ' + url + '\n');
                    obj._funcs.push( function() { 
                        dump('SOUND('+obj.sig+'): playing file = ' + url + '\n');
                        obj.SOUND.play( url2 ); 
                    } );
                } else {
                    dump('SOUND('+obj.sig+'): playing file = ' + url + '\n');
                    obj.SOUND.play( url2 );
                }
            }
        } catch(E) {
            try { if (data.no_sound == 'undefined' || data.no_sound == false || data.no_sound == 'false') obj.SOUND.beep(); } catch(F) { 
                dump('beep(): ' + F + '\n');
            }
            dump('play_url(): ' + E + '\n');
        }
    },

    'event' : function event(evt) {
        var key = 'AUDIO_' + arguments.callee.name + '_' + evt.textcode;
        dump('SOUND('+this.sig+'): key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'special' : function special(e) {
        var key = 'AUDIO_' + arguments.callee.name + '_' + e;
        dump('SOUND('+this.sig+'): key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'good' : function good(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND('+this.sig+'): key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'bad' : function bad(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND('+this.sig+'): key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'horrible' : function horrible(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND('+this.sig+'): key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'circ_good' : function circ_good(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND('+this.sig+'): key = ' + key + '\n');
        this.play_url( urls[key] );
    },

    'circ_bad' : function circ_bad(e){
        var key = 'AUDIO_' + arguments.callee.name;
        dump('SOUND('+this.sig+'): key = ' + key + '\n');
        this.play_url( urls[key] );
    }
}

dump('exiting util/sound.js\n');
