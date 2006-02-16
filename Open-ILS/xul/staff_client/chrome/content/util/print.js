dump('entering util/print.js\n');

if (typeof util == 'undefined') util = {};
util.print = function () {

	netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init( { 'via':'stash' } );
	JSAN.use('util.window'); this.win = new util.window();

	return this;
};

util.print.prototype = {

	'simple' : function(msg,params) {

		if (!params) params = {};

		var obj = this;

		obj.data.last_print = msg; obj.data.stash('last_print');

		var silent = false;
		if (params && params.no_prompt && params.no_prompt == true) silent = true;

		var w = obj.win.open('data:text/html,<html>' + window.escape(msg) + '</html>','temp','chrome,resizable');

		w.minimize();

		setTimeout(
			function() {
				try {
					obj.NSPrint(w, silent, params);
				} catch(E) {
					obj.error.sdump('D_ERROR','util.print.simple: ' + E);
					w.print();
				}
				w.minimize(); w.close();
			}, 0
		);
	},

	'NSPrint' : function(w,silent,params) {
		if (!w) w = window;
		try {
			var webBrowserPrint = w
				.QueryInterface(Components.interfaces.nsIInterfaceRequestor)
				.getInterface(Components.interfaces.nsIWebBrowserPrint);
			this.error.sdump('D_PRINT','webBrowserPrint = ' + webBrowserPrint);
			if (webBrowserPrint) {
				var gPrintSettings = GetPrintSettings();
				if (silent) gPrintSettings.printSilent = true;
				else gPrintSettings.printSilent = false;
				if (params) {
					gPrintSettings.marginTop = 0;
					gPrintSettings.marginLeft = 0;
					gPrintSettings.marginBottom = 0;
					gPrintSettings.marginRight = 0;
					if (params.marginLeft) gPrintSettings.marginLeft = params.marginLeft;
				}
				gPrintSettings.headerStrLeft = '';
				gPrintSettings.headerStrCenter = '';
				gPrintSettings.headerStrRight = '';
				gPrintSettings.footerStrLeft = '';
				gPrintSettings.footerStrCenter = '';
				gPrintSettings.footerStrRight = '';
				this.error.sdump('D_PRINT','gPrintSettings = ' + js2JSON(gPrintSettings));
				//alert('gPrintSettings = ' + js2JSON(gPrintSettings));
				webBrowserPrint.print(gPrintSettings, null);
				//alert('Should be printing\n');
				this.error.sdump('D_PRINT','Should be printing\n');
			} else {
				//alert('Should not be printing\n');
				this.error.sdump('D_PRINT','Should not be printing\n');
			}
		} catch (e) {
			//alert('Probably not printing: ' + e);
			// Pressing cancel is expressed as an NS_ERROR_ABORT return value,
			// causing an exception to be thrown which we catch here.
			// Unfortunately this will also consume helpful failures, so add a
			this.error.sdump('D_PRINT','PRINT EXCEPTION: ' + js2JSON(e) + '\n');
			// if you need to debug
		}

	},

	'GetPrintSettings' : function() {
		try {
			var pref = Components.classes["@mozilla.org/preferences-service;1"]
				.getService(Components.interfaces.nsIPrefBranch);
			if (pref) {
				this.gPrintSettingsAreGlobal = pref.getBoolPref("print.use_global_printsettings", false);
				this.gSavePrintSettings = pref.getBoolPref("print.save_print_settings", false);
			}
 
			var printService = Components.classes["@mozilla.org/gfx/printsettings-service;1"]
				.getService(Components.interfaces.nsIPrintSettingsService);
			if (this.gPrintSettingsAreGlobal) {
				this.gPrintSettings = printService.globalPrintSettings;
				this.setPrinterDefaultsForSelectedPrinter(printService);
			} else {
				this.gPrintSettings = printService.newPrintSettings;
			}
		} catch (e) {
			this.error.sdump('D_PRINT',"GetPrintSettings() "+e+"\n");
			//alert("GetPrintSettings() "+e+"\n");
		}
 
		return this.gPrintSettings;
	},

	'setPrinterDefaultsForSelectedPrint' : function (aPrintService) {
		if (this.gPrintSettings.printerName == "") {
			this.gPrintSettings.printerName = aPrintService.defaultPrinterName;
		}
 
		// First get any defaults from the printer 
		aPrintService.initPrintSettingsFromPrinter(this.gPrintSettings.printerName, this.gPrintSettings);
 
		// now augment them with any values from last time
		aPrintService.initPrintSettingsFromPrefs(this.gPrintSettings, true, this.gPrintSettings.kInitSaveAll);
	}
}

dump('exiting util/print.js\n');
