sdump('D_WIN','Loading win.js\n');

function s_alert(s) {
	// alert() replacement, intended to stop barcode scanners from "scanning through" the dialog

	// get a reference to the prompt service component.
	var promptService = Components.classes["@mozilla.org/embedcomp/prompt-service;1"]
		.getService(Components.interfaces.nsIPromptService);

	// set the buttons that will appear on the dialog. It should be
	// a set of constants multiplied by button position constants. In this case,
	// three buttons appear, Save, Cancel and a custom button.
	//var flags=promptService.BUTTON_TITLE_OK * promptService.BUTTON_POS_0 +
	//	promptService.BUTTON_TITLE_CANCEL * promptService.BUTTON_POS_1 +
	//	promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_2;
	var flags = promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_0;

	// display the dialog box. The flags set above are passed
	// as the fourth argument. The next three arguments are custom labels used for
	// the buttons, which are used if BUTTON_TITLE_IS_STRING is assigned to a
	// particular button. The last two arguments are for an optional check box.
	var check = {};
	sdump('D_WIN','s_alert: ' + s);
	promptService.confirmEx(window,"ALERT",
		s,
		flags, 
		"Enter", null, null, 
		"Check this box to confirm this message", 
		check
	);
	if (!check.value) {
		snd_bad();
		s_alert(s);
	}
}

function new_window(chrome,params) {
	var name = self.name + '_' + ++mw.G['window_name_increment'];
	var options = 'chrome,resizable=yes,scrollbars=yes,width=800,height=600,fullscreen=yes';
	try {
		if (params) {
			if (params['window_name']) { name = params.window_name; }
			if (params['window_options']) { options = params.window_options; }
		}
	} catch(E) {
	}
	//var w = window.open(
	var w = SafeWindowOpen(
		chrome,
		name,
		options
	);
	if (w) {
		if (w != self) { 
			w.parentWindow = self;
			w.mw = mw;
			//register_window(w); 
		}
		w.am_i_a_top_level_tab = false;
		if (params) {
			w.params = params;
		}
	}
	return w;
}


// From: Bryan White on netscape.public.mozilla.xpfe, Oct 13, 2004
// Message-ID: <ckjh7a$18q1@ripley.netscape.com>
// Modified to return window handler, and do errors differently
function SafeWindowOpen(url,title,features)
{
	var w;

   netscape.security.PrivilegeManager
     .enablePrivilege("UniversalXPConnect");    
   const CI = Components.interfaces;
   const PB =
     Components.classes["@mozilla.org/preferences-service;1"]
     .getService(CI.nsIPrefBranch);

   var blocked = false;
   try
   {
     // pref 'dom.disable_open_during_load' is the main popup
     // blocker preference
     blocked = PB.getBoolPref("dom.disable_open_during_load");
     if(blocked)
       PB.setBoolPref("dom.disable_open_during_load",false);
     w = window.open(url,title,features);
   }
   catch(e)
   {
     //alert("SafeWindowOpen error:\n\n" + e);
     handle_error(e);
   }
   if(blocked)
     PB.setBoolPref("dom.disable_open_during_load",true);

	return w;
} 

function register_AppShell(w) {
	sdump('D_WIN',arg_dump(arguments,{0:true}));
	mw.G.appshell_list.push(w);
}

function unregister_AppShell(w) {
	sdump('D_WIN',arg_dump(arguments,{0:true}));
	mw.G.appshell_list = filter_list( mw.G.appshell_list, function(e){return(e!=w);} );
}

function register_window(w) {
	sdump('D_WIN',arg_dump(arguments,{0:true}));
	mw.G.win_list.push(w);
	mw.G.last_win = w;
}

function unregister_window(w) {
	sdump('D_WIN',arg_dump(arguments,{0:true}));
	mw.G.win_list = filter_list( mw.G.win_list, function(e){return(e!=w);} );
	mw.G.last_win = mw.G.win_list[ mw.G.win_list.length - 1 ];
}

function close_all_windows() {
	sdump('D_WIN',arg_dump(arguments));
	var w;
	for (var i in mw.G.appshell_list) {
		sdump('D_WIN','\tconsidering ' + i + '...');
		if (mw.G.win_list[i] != mw) {
			sdump('D_WIN','closing');
			var w = mw.G.win_list[i];
			try { w.close(); } catch (E) {}
			//unregister_window( w );
		}
		sdump('D_WIN','\n');
	}
	mw.close();
}

function register_document(d) {
	sdump('D_WIN',arg_dump(arguments,{0:true}));
	mw.G.doc_list[d.toString()] = d;
	mw.G.last_doc = d;
}

function unregister_document(d) {
	sdump('D_WIN',arg_dump(arguments,{0:true}));
	try { delete mw.G.doc_list[d.toString()]; } catch(E) { mw.G.doc_list[d.toString()] = false; }	
}


