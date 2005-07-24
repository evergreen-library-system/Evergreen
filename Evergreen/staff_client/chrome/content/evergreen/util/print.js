sdump('D_TRACE','Loading print.js\n');

var print_crlf = '<br />\r\n';

// Higher-level

function print_checkout_receipt(params) {
	sdump('D_PRINT',arg_dump(arguments));
	var s = '';
	if (params.header) { s += print_template_replace(params.header, params); }
	for (var i = 0; i < params.au.checkouts().length; i++) {
		params.current_circ = params.au.checkouts()[i].circ;
		params.current_copy = params.au.checkouts()[i].copy;
		params.current_mvr = params.au.checkouts()[i].record;
		params.current_index = i;
		s += print_template_replace(params.line_item, params); 
	}
	if (params.footer) { s += print_template_replace(params.footer, params); }
	s = s.replace( /\n/g, print_crlf );
	sPrint( s );
}

function print_template_replace(s,params) {
		try{s=s.replace(/%LIBRARY%/g,params.lib.name());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%PINES_CODE%/g,params.lib.shortname());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}

		try{s=s.replace(/%PATRON_LASTNAME%/g,params.au.family_name());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%PATRON_FIRSTNAME%/g,params.au.first_given_name());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%PATRON_MIDDLENAME%/g,params.au.second_given_name());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%PATRON_BARCODE%/g,params.au.card().barcode());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}

		try{s=s.replace(/%TODAY%/g,new Date());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_m%/g,formatted_date(new Date(),'%m'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_d%/g,formatted_date(new Date(),'%d'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_Y%/g,formatted_date(new Date(),'%Y'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_H%/g,formatted_date(new Date(),'%H'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_I%/g,formatted_date(new Date(),'%I'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_M%/g,formatted_date(new Date(),'%M'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_D%/g,formatted_date(new Date(),'%D'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_F%/g,formatted_date(new Date(),'%F'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		
		try{s=s.replace(/%OUT%/g,params.current_circ.xact_start());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_m%/g,formatted_date(params.current_circ.xact_start(),'%m'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_d%/g,formatted_date(params.current_circ.xact_start(),'%d'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_Y%/g,formatted_date(params.current_circ.xact_start(),'%Y'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_H%/g,formatted_date(params.current_circ.xact_start(),'%H'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_I%/g,formatted_date(params.current_circ.xact_start(),'%I'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_M%/g,formatted_date(params.current_circ.xact_start(),'%M'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_D%/g,formatted_date(params.current_circ.xact_start(),'%D'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_F%/g,formatted_date(params.current_circ.xact_start(),'%F'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}

		try{s=s.replace(/%DUE%/g,params.current_circ.due_date());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_m%/g,formatted_date(params.current_circ.due_date(),'%m'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_d%/g,formatted_date(params.current_circ.due_date(),'%d'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_Y%/g,formatted_date(params.current_circ.due_date(),'%Y'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_H%/g,formatted_date(params.current_circ.due_date(),'%H'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_I%/g,formatted_date(params.current_circ.due_date(),'%I'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_M%/g,formatted_date(params.current_circ.due_date(),'%M'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_D%/g,formatted_date(params.current_circ.due_date(),'%D'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_F%/g,formatted_date(params.current_circ.due_date(),'%F'));}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}

		try{s=s.replace(/%DURATION%/g,params.curent_circ.duration());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		
		try{s=s.replace(/%COPY_BARCODE%/g,params.curent_copy.barcode());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%TITLE%/g,params.current_mvr.title());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%AUTHOR%/g,params.current_mvr.author());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%PUBLISHER%/g,params.current_mvr.publisher());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}
		try{s=s.replace(/%PUBDATE%/g,params.current_mvr.pubdate());}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}

		try{s=s.replace(/%NUMBER%/g,params.current_index);}catch(E){sdump('D_ERROR',js2JSON(E)+'\n');}

		return s;
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
			//w.close();
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
 
