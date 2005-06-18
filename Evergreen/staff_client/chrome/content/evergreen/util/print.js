dump('Loading print.js\n');

function sPrint(s) {
	//var w = window.open('about:blank','print_win','alwaysLowered,minimizable,resizable,height=100,width=100,sizemode=minimized');
	var w = SafeWindowOpen('about:blank','print_win','alwaysLowered,minimizable,resizable,height=100,width=100,sizemode=minimized');
	this.focus();
	w.document.write(s);
	//w.print();
	NSPrint(w);
	w.close();
}

function sPrint_old(s) {
	dump('Printing "' + s + '"\n');
	//var deck = mw.document.getElementById('main_deck');
	var iframe = mw.document.getElementById('print_frame');
	//deck.appendChild(iframe);
	iframe.setAttribute('src','about:blank');
	/*while (iframe.contentWindow.document.lastChild) { 
		iframe.contentWindow.document.removeChild(
			iframe.contentWindow.document.lastChild
		);
	}*/
	//iframe.contentDocument.write(s);
	iframe.contentWindow.document.write(s);
	NSPrint2(iframe.contentWindow);
	//deck.removeChild(iframe);
}

function NSPrint(w)
{
	if (!w) { w = this; }
	try {
		var webBrowserPrint = w
			.QueryInterface(Components.interfaces.nsIInterfaceRequestor)
			.getInterface(Components.interfaces.nsIWebBrowserPrint);
		if (webBrowserPrint) {
			var gPrintSettings = GetPrintSettings();
			gPrintSettings.printSilent = true;
			webBrowserPrint.print(gPrintSettings, null);
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
			//alert('Should be printing\n');
		} else {
			//alert('Should not be printing\n');
		}
	} catch (e) {
		//alert('Probably not printing: ' + e);
	// Pressing cancel is expressed as an NS_ERROR_ABORT return value,
	// causing an exception to be thrown which we catch here.
	// Unfortunately this will also consume helpful failures, so add a
	 	dump('PRINT EXCEPTION: ' + js2JSON(e) + '\n'); // if you need to debug
	}
}

function NSPrint2(w) {
	if (!w) { w = this; }
	try {
		var webBrowserPrint = w
			.QueryInterface(Components.interfaces.nsIInterfaceRequestor)
			.getInterface(Components.interfaces.nsIWebBrowserPrint);
		if (webBrowserPrint) {
			webBrowserPrint.print(null, null);
			//alert('Should be printing\n');
		} else {
			//alert('Should not be printing\n');
		}
	} catch (e) {
		//alert('Probably not printing: ' + e);
	// Pressing cancel is expressed as an NS_ERROR_ABORT return value,
	// causing an exception to be thrown which we catch here.
	// Unfortunately this will also consume helpful failures, so add a
	 	dump('PRINT EXCEPTION: ' + js2JSON(e) + '\n'); // if you need to debug
	}

}

var gPrintSettings = null;

function GetPrintSettings()
 {
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
     dump("GetPrintSettings() "+e+"\n");
     alert("GetPrintSettings() "+e+"\n");
   }
 
   return gPrintSettings;
 }

function setPrinterDefaultsForSelectedPrinter(aPrintService)
 {
   if (gPrintSettings.printerName == "") {
     gPrintSettings.printerName = aPrintService.defaultPrinterName;
   }
 
   // First get any defaults from the printer 
   aPrintService.initPrintSettingsFromPrinter(gPrintSettings.printerName, gPrintSettings);
 
   // now augment them with any values from last time
   aPrintService.initPrintSettingsFromPrefs(gPrintSettings, true, gPrintSettings.kInitSaveAll);
 }
 
