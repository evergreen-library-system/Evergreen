sdump('D_TRACE','Loading print.js\n');

var print_crlf = '<br />\r\n';

// Higher-level

function print_checkout_receipt(params) {
	sdump('D_PRINT',arg_dump(arguments));


}

// Lower-level

function sPrint(s) {
	sdump('D_PRINT',arg_dump(arguments));
	var w = new_window('data:text/html,<html>' + s + '</html>\r\n', { 'window_name':'LastPrint' });
	setTimeout(
		function() {
			w.minimize(); mw.minimize();
			this.focus();
			NSPrint(w);
			w.minimize(); mw.minimize();
			w.close();
		},0
	);
}

function NSPrint(w)
{
	sdump('D_PRINT',arg_dump(arguments));
	if (!w) { w = this; }
	try {
		var webBrowserPrint = w
			.QueryInterface(Components.interfaces.nsIInterfaceRequestor)
			.getInterface(Components.interfaces.nsIWebBrowserPrint);
		if (webBrowserPrint) {
			var gPrintSettings = GetPrintSettings();
			gPrintSettings.printSilent = true;
                        gPrintSettings.marginTop = 0;
                        gPrintSettings.marginLeft = 0;
                        gPrintSettings.marginBottom = 0;
                        gPrintSettings.marginRight = 0;
                        gPrintSettings.headerStrLeft = '';
                        gPrintSettings.headerStrCenter = '';
                        gPrintSettings.headerStrRight = '';
                        gPrintSettings.footerStrLeft = '';
                        gPrintSettings.footerStrCenter = '';
                        gPrintSettings.footerStrRight = '';
			webBrowserPrint.print(gPrintSettings, null);
			//alert('Should be printing\n');
		} else {
			//alert('Should not be printing\n');
		}
	} catch (e) {
		//alert('Probably not printing: ' + e);
	// Pressing cancel is expressed as an NS_ERROR_ABORT return value,
	// causing an exception to be thrown which we catch here.
	// Unfortunately this will also consume helpful failures, so add a
	 	sdump('D_PRINT','PRINT EXCEPTION: ' + js2JSON(e) + '\n'); // if you need to debug
	}
}

var gPrintSettings = null;

function GetPrintSettings()
 {
	sdump('D_PRINT',arg_dump(arguments));
   try {
     if (gPrintSettings == null) {
       var pref = Components.classes["@mozilla.org/preferences-service;1"]
                            .getService(Components.interfaces.nsIPrefBranch);
       if (pref) {
         gPrintSettingsAreGlobal = pref.getBoolPref("print.use_global_printsettings", false);
         gSavePrintSettings = pref.getBoolPref("print.save_print_settings", false);
       }
 
       var printService = Components.classes["@mozilla.org/gfx/printsettings-service;1"]
                                         .getService(Components.interfaces.nsIPrintSettingsService);
       if (gPrintSettingsAreGlobal) {
         gPrintSettings = printService.globalPrintSettings;
         setPrinterDefaultsForSelectedPrinter(printService);
       } else {
         gPrintSettings = printService.newPrintSettings;
       }
     }
   } catch (e) {
     sdump('D_PRINT',"GetPrintSettings() "+e+"\n");
     alert("GetPrintSettings() "+e+"\n");
   }
 
   return gPrintSettings;
 }

function setPrinterDefaultsForSelectedPrinter(aPrintService)
 {
	sdump('D_PRINT',arg_dump(arguments));
   if (gPrintSettings.printerName == "") {
     gPrintSettings.printerName = aPrintService.defaultPrinterName;
   }
 
   // First get any defaults from the printer 
   aPrintService.initPrintSettingsFromPrinter(gPrintSettings.printerName, gPrintSettings);
 
   // now augment them with any values from last time
   aPrintService.initPrintSettingsFromPrefs(gPrintSettings, true, gPrintSettings.kInitSaveAll);
 }
 
