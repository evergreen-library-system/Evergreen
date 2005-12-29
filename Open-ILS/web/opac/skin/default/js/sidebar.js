/* set up the colors in the sidebar 
	Disables/Enables certain components based on various state data */

attachEvt("common", "init", initSideBar);
attachEvt("common", "init", setSidebarLinks);

attachEvt("common", "unload", sidebarTreesFree );

function initSideBar() {
	var page = findCurrentPage();

	if( page == MRESULT ) 
		unHideMe($("sidebar_results_wrapper"));

	if( page == RRESULT ) {
		unHideMe($("sidebar_results_wrapper"));
		unHideMe(G.ui.sidebar[MRESULT]);
		$("sidebar_title_group_results").setAttribute("href", buildOPACLink({ page: MRESULT }));
	}

	if( page == RDETAIL ) {
		unHideMe($("sidebar_results_wrapper"));
		$("sidebar_title_group_results").setAttribute("href", buildOPACLink({ page: MRESULT }));
		unHideMe(G.ui.sidebar[MRESULT]);
		$("sidebar_title_results").setAttribute("href", buildOPACLink({ page : RRESULT }));
		unHideMe(G.ui.sidebar[RRESULT]);
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
}

/* sets up the login ui components */
var loginBoxVisible = false;

function loginDance() {
	if(doLogin()) {
		showCanvas();
		G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
		unHideMe(G.ui.sidebar.logoutbox);
		unHideMe(G.ui.sidebar.logged_in_as);
		hideMe(G.ui.sidebar.loginbox);
		runEvt("common", "loggedIn");
	}
}

function initLogin() {

	G.ui.login.button.onclick = loginDance;
	G.ui.login.username.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) loginDance();};
	G.ui.login.password.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) loginDance();};

	if(loginBoxVisible) {
		showCanvas();
	} else {
		swapCanvas(G.ui.login.box);
		try{G.ui.login.username.focus();}catch(e){}
	}

	loginBoxVisible = !loginBoxVisible;
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

