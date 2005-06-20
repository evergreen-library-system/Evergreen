sdump('D_TRACE','Loading sound.js\n');

function xp_sound_init() {
	var SOUNDContractID = "@mozilla.org/sound;1";
	var SOUNDIID        = Components.interfaces.nsISound;
	var SOUND           = Components.classes[SOUNDContractID].createInstance(SOUNDIID);
	return SOUND;
}

function snd_bad() {
	mw.G.sound.play( xp_url_init('chrome://evergreen/skin/media/sounds/redalert.wav') );
}

function snd_really_bad() {
	mw.G.sound.play( xp_url_init('chrome://evergreen/skin/media/sounds/die.wav') );
}

function snd_good() {
	mw.G.sound.play( xp_url_init('chrome://evergreen/skin/media/sounds/turn.wav') );
}

function snd_circ_good() {
	mw.G.sound.play( xp_url_init('chrome://evergreen/skin/media/sounds/clicked.wav') );
}

function snd_circ_bad() {
	mw.G.sound.play( xp_url_init('chrome://evergreen/skin/media/sounds/cow.wav') );
}

function snd_logon() {

}

function snd_logoff() {

}

function snd_exit() {

}


