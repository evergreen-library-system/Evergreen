sdump('D_TRACE','Loading print.js\n');

var print_crlf = '<br />\r\n';

// Higher-level

function print_itemsout_receipt(params,sample_view) {
	print_circ_receipt('itemsout',params,sample_view);
}

function print_checkout_receipt(params,sample_view) {
	print_circ_receipt('checkout',params,sample_view);
}

function print_circ_receipt(circ_type,params,sample_view) {
	sdump('D_PRINT',arg_dump(arguments));
	var s = ''; params.current_circ = new circ(); params.current_copy = new acp(); params.current_mvr = new mvr();
	if (params.header) { s += print_template_replace(params.header, params); }
	var circs;
	switch(circ_type) {
		case 'itemsout' : circs = params.au.checkouts(); break;
		case 'checkout' : circs = params.au._current_checkouts; break;
	}
	for (var i = 0; i < circs.length; i++) {
		params.current_circ = circs()[i].circ;
		params.current_copy = circs()[i].copy;
		params.current_mvr = circs()[i].record;
		params.current_index = i;
		s += print_template_replace(params.line_item, params); 
	}
	if (params.footer) { s += print_template_replace(params.footer, params); }
	s = s.replace( /\n/g, print_crlf );
	if (sample_view) {
		sample_view.setAttribute( 'src', 'data:text/html,<html>' + s + '</html>\r\n' );
	} else {
		sPrint( s );
	}
}

function print_template_replace(s,params) {

		function trunc(t) {
			if (params.truncate) {
				try {
					return t.toString().substr(0,params.truncate);
				} catch(E) {
					return t;
				}
			} else {
				return t;
			}
		}
		function ttrunc(t) {
			if (params.title_truncate) {
				try {
					return t.toString().substr(0,params.title_truncate);
				} catch(E) {
					return t;
				}
			} else {
				return t;
			}
		}
		function atrunc(t) {
			if (params.author_truncate) {
				try {
					return t.toString().substr(0,params.author_truncate);
				} catch(E) {
					return t;
				}
			} else {
				return t;
			}
		}



		var b = s.match( /%TRUNC.{0,3}:\s*(\d+)%/ );
		if (b) params.truncate = b[1];

		try{s=s.replace(/%TRUNC.{0,3}:\s*\d+%/g,'');}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%LIBRARY%/g,trunc(params.lib.name()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%PINES_CODE%/g,trunc(params.lib.shortname()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}

		try{s=s.replace(/%PATRON_LASTNAME%/g,trunc(params.au.family_name()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%PATRON_FIRSTNAME%/g,trunc(params.au.first_given_name()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%PATRON_MIDDLENAME%/g,trunc(params.au.second_given_name()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%PATRON_BARCODE%/g,trunc(params.au.card().barcode()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}

		try{s=s.replace(/%STAFF_LASTNAME%/g,trunc(params.staff.family_name()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%STAFF_FIRSTNAME%/g,trunc(params.staff.first_given_name()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%STAFF_MIDDLENAME%/g,trunc(params.staff.second_given_name()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%STAFF_BARCODE%/g,trunc(params.staff.card().barcode()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}

		try{s=s.replace(/%TODAY%/g,trunc(new Date()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_m%/g,trunc(formatted_date(new Date(),'%m')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_d%/g,trunc(formatted_date(new Date(),'%d')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_Y%/g,trunc(formatted_date(new Date(),'%Y')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_H%/g,trunc(formatted_date(new Date(),'%H')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_I%/g,trunc(formatted_date(new Date(),'%I')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_M%/g,trunc(formatted_date(new Date(),'%M')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_D%/g,trunc(formatted_date(new Date(),'%D')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%TODAY_F%/g,trunc(formatted_date(new Date(),'%F')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		
		try{s=s.replace(/%OUT%/g,trunc(params.current_circ.xact_start()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_m%/g,trunc(formatted_date(params.current_circ.xact_start(),'%m')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_d%/g,trunc(formatted_date(params.current_circ.xact_start(),'%d')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_Y%/g,trunc(formatted_date(params.current_circ.xact_start(),'%Y')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_H%/g,trunc(formatted_date(params.current_circ.xact_start(),'%H')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_I%/g,trunc(formatted_date(params.current_circ.xact_start(),'%I')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_M%/g,trunc(formatted_date(params.current_circ.xact_start(),'%M')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_D%/g,trunc(formatted_date(params.current_circ.xact_start(),'%D')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%OUT_F%/g,trunc(formatted_date(params.current_circ.xact_start(),'%F')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}

		try{s=s.replace(/%DUE%/g,trunc(params.current_circ.due_date()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_m%/g,trunc(formatted_date(params.current_circ.due_date(),'%m')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_d%/g,trunc(formatted_date(params.current_circ.due_date(),'%d')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_Y%/g,trunc(formatted_date(params.current_circ.due_date(),'%Y')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_H%/g,trunc(formatted_date(params.current_circ.due_date(),'%H')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_I%/g,trunc(formatted_date(params.current_circ.due_date(),'%I')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_M%/g,trunc(formatted_date(params.current_circ.due_date(),'%M')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_D%/g,trunc(formatted_date(params.current_circ.due_date(),'%D')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%DUE_F%/g,trunc(formatted_date(params.current_circ.due_date(),'%F')));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}

		try{s=s.replace(/%DURATION%/g,trunc(params.current_circ.duration()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		
		try{s=s.replace(/%COPY_BARCODE%/g,trunc(params.current_copy.barcode()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		
		var tb = s.match( /%TITLE:?\s*(\d*)%/ );
		if (tb) params.title_truncate = tb[1];

		try{s=s.replace(/%TITLE:?\s*\d*%/g,ttrunc(params.current_mvr.title()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}

		var ab = s.match( /%AUTHOR:?\s*(\d*)%/ );
		if (ab) params.author_truncate = ab[1];

		try{s=s.replace(/%AUTHOR%/g,atrunc(params.current_mvr.author()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%PUBLISHER%/g,trunc(params.current_mvr.publisher()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}
		try{s=s.replace(/%PUBDATE%/g,trunc(params.current_mvr.pubdate()));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}

		try{s=s.replace(/%NUMBER%/g,(params.current_index+1));}
			catch(E){sdump('D_ERROR','string = <' + s + '> error = ' + js2JSON(E)+'\n');}

		return s;
}

// Lower-level

function sPrint(s) {
	sdump('D_PRINT',arg_dump(arguments));
	var w = new_window('data:text/html,<html>' + s + '</html>\r\n', { 'window_name':'LastPrint' });
	w.minimize(); mw.minimize();
	setTimeout(
		function() {
			NSPrint(w); w.minimize(); w.close(); mw.minimize();
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
			/*
                        gPrintSettings.marginTop = 0;
                        gPrintSettings.marginLeft = 0;
                        gPrintSettings.marginBottom = 0;
                        gPrintSettings.marginRight = 0;
			*/
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
 
