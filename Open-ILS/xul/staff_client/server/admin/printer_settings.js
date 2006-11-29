var myPackageDir = 'open_ils_staff_client'; var IAMXUL = true; var g = {};

function my_init() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
				if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('/xul/server/');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for printer_settings.xul');

		JSAN.use('util.print'); g.print = new util.print();

		/*
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		g.PSSVC = Components.classes["@mozilla.org/gfx/printsettings-service;1"].getService(Components.interfaces.nsIPrintSettingsService);
		g.PO = Components.classes["@mozilla.org/gfx/printsettings-service;1"].getService(Components.interfaces.nsIPrintOptions);
		g.PPSVC = Components.classes["@mozilla.org/embedcomp/printingprompt-service;1"].getService(Components.interfaces.nsIPrintingPromptService);
		g.settings = g.PSSVC.globalPrintSettings;
		*/

	} catch(E) {
		try { g.error.standard_unexpected_error_dialog('admin/printer_settings.xul',E); } catch(F) { alert(E); }
	}
}

g.page_settings = function() {
	netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
	g.print.page_settings();
	g.print.save_settings();
}

g.printer_settings = function() {
	netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
	var w = document.getElementById('sample').contentWindow;
	g.print.NSPrint(w ? w : window);
	g.print.save_settings();
}

g.save_settings = function() { g.print.save_settings(); }
