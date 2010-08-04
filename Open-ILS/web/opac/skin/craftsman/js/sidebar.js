/* set up the colors in the sidebar 
	Disables/Enables certain components based on various state data */

attachEvt("common", "init", initSideBar);
attachEvt("common", "init", setSidebarLinks);

attachEvt("common", "unload", sidebarTreesFree );

function prevRResults() {
	return buildOPACLink({ page : RRESULT });
}

function prevMResults() {
	return buildOPACLink({ page : MRESULT });
}

function initSideBar() {
	var page = findCurrentPage();

	if( page == MRESULT ) 
		unHideMe($("sidebar_results_wrapper"));

	if( page == RRESULT ) {
		unHideMe($("sidebar_results_wrapper"));
		unHideMe(G.ui.sidebar[MRESULT]);
		if( getRtype() == RTYPE_MRID )
			$("sidebar_title_group_results").setAttribute("href", prevMResults());
		else hideMe($("sidebar_title_group_results").parentNode);
	}

	if( page == RDETAIL ) {
		unHideMe($("sidebar_results_wrapper"));


		unHideMe(G.ui.sidebar[MRESULT]);
		if(getRtype())
			$("sidebar_title_results").setAttribute("href", prevRResults());
		unHideMe(G.ui.sidebar[RRESULT]);

		if( getRtype() == RTYPE_MRID )
			$("sidebar_title_group_results").setAttribute("href", prevMResults());
		else hideMe($("sidebar_title_group_results").parentNode);
	}

	unHideMe(G.ui.sidebar[page]);
	addCSSClass(G.ui.sidebar[page], "sidebar_item_active");

	/* if we're logged in, show it and replace the Login link with the Logout link */
	if(grabUser()) {
		G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
		unHideMe(G.ui.sidebar.logoutbox);
		unHideMe(G.ui.sidebar.logged_in_as);
		hideMe(G.ui.sidebar.loginbox);
	}

	if(G.ui.sidebar.login) G.ui.sidebar.login.onclick = initLogin;
	if(G.ui.sidebar.logout) G.ui.sidebar.logout.onclick = doLogout; 

	if(isXUL()) hideMe( G.ui.sidebar.logoutbox );
}

/* sets up the login ui components */
var loginBoxVisible = false;

function loginDance() {

	if(doLogin(true)) {

		if(!strongPassword( G.ui.login.password.value ) ) {

			cookieManager.write(COOKIE_SES, "");
			hideMe($('login_table'));
			unHideMe($('change_pw_table'));
			$('change_pw_current').focus();
			$('change_pw_button').onclick = changePassword;
			setEnterFunc($('change_pw_2'), changePassword);

		} else {
			loggedInOK();
		}
	}
}

function loggedInOK() {
	showCanvas();
	G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
	unHideMe(G.ui.sidebar.logoutbox);
	unHideMe(G.ui.sidebar.logged_in_as);
	hideMe(G.ui.sidebar.loginbox);
	runEvt( 'common', 'loggedIn');
	
	var org = G.user.prefs[PREF_DEF_LOCATION];
	if(!org) org = G.user.home_ou();

	var depth = G.user.prefs[PREF_DEF_DEPTH];
	if(! ( depth && depth <= findOrgDepth(org)) ) 
		depth = findOrgDepth(org);

	runEvt( "common", "locationChanged", org, depth);
}


function changePassword() {

	var pc = $('change_pw_current').value;
	var p1 = $('change_pw_1').value;
	var p2 = $('change_pw_2').value;

	if( p1 != p2 ) {
		alert($('pw_no_match').innerHTML);
		return;
	}

	if(!strongPassword(p2, true) ) return;

	var req = new Request(UPDATE_PASSWORD, G.user.session, p2, pc );
	req.send(true);
	if(req.result()) {
		alert($('pw_update_successful').innerHTML);
		loggedInOK();
	}
}

var pwRegexSetting;
function strongPassword(pass, alrt) {

    /* first, let's see if there is a configured regex */
    if(!pwRegexSetting) {
        var regex = fetchOrgSettingDefault(G.user.home_ou(), 'global.password_regex');
        if(regex) {
            if(pass.match(new RegExp(regex))) {
                return true;
            } else {
                if(alrt)
	               alert($('pw_not_strong').innerHTML);
                return false;
            }
        }
    }

    /* no regex configured, use the default */

	var good = false;

	do {

		if(pass.length < 7) break;
		if(!pass.match(/.*\d+.*/)) break;
		if(!pass.match(/.*[A-Za-z]+.*/)) break;
		good = true;

	} while(0);

	if(!good && alrt) alert($('pw_not_strong').innerHTML);
	return good;
}

function initLogin() {

	G.ui.login.button.onclick = loginDance;
	G.ui.login.username.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) loginDance();};
	G.ui.login.password.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) loginDance();};

//	if(loginBoxVisible) {
//		showCanvas();
//	} else {
		swapCanvas(G.ui.login.box);
		try{G.ui.login.username.focus();}catch(e){}
//	}

//	loginBoxVisible = !loginBoxVisible;
	G.ui.login.cancel.onclick = showCanvas;
	if(findCurrentPage() == MYOPAC) 
		G.ui.login.cancel.onclick = goHome;
}

function setSidebarLinks() {
	G.ui.sidebar.home_link.setAttribute("href", buildOPACLink({page:HOME}));
	G.ui.sidebar.advanced_link.setAttribute("href", buildOPACLink({page:ADVANCED}));
	G.ui.sidebar.myopac_link.setAttribute("href", buildOPACLink({page:MYOPAC}, false, true));
}

function sidebarTreesFree() {
	removeChildren($(subjectSidebarTree.rootid));
	removeChildren($(authorSidebarTree.rootid));
	removeChildren($(seriesSidebarTree.rootid));
	subjectSidebarTree = null;
	authorSidebarTree = null;
	seriesSidebarTree = null;
}




/* --------------------------------------------------------------------------------- */
/* Code to support GALILEO links for PINES.  Fails gracefully
/* --------------------------------------------------------------------------------- */
attachEvt('common', 'init', buildEGGalLink);
function buildEGGalLink() {

	/* we're in a lib, nothing to do here */
	if( getOrigLocation() ) return;
	if(!$('eg_gal_link')) return;

	//var link = 'http://demo.galib.uga.edu/express?pinesid=';
	var link = 'http://www.galileo.usg.edu/express?pinesid=';
	if(grabUser()) {
		$('eg_gal_link').setAttribute('href', link + G.user.session);
		return;
	}

	$('eg_gal_link').setAttribute('href', 'javascript:void(0);');
	$('eg_gal_link').setAttribute('target', '');
	$('eg_gal_link').onclick = function() {
		/* we're not logged in.  go ahead and login */
		detachAllEvt('common','locationChanged');
		detachAllEvt('common','loggedIn');
		attachEvt('common','loggedIn', function() { goTo(link + G.user.session); })
		initLogin();
	};
}
/* --------------------------------------------------------------------------------- */


