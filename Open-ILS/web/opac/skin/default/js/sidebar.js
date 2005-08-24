/* set up the colors in the sidebar 
	Disables/Enables certain components based on various state data */

attachEvt("common", "init", initSideBar);
attachEvt("common", "init", setSidebarLinks);

function initSideBar() {

	for( var p in G.ui.sidebar ) 
		removeCSSClass(p, config.css.color_2);

	var page = findCurrentPage();
	unHideMe(G.ui.sidebar[page]);
	addCSSClass(G.ui.sidebar[page], config.css.color_2);

	/* if we're logged in, show it and replace the Login link with the Logout link */
	if(grabUser()) {
		G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
		unHideMe(G.ui.sidebar.logoutbox);
		unHideMe(G.ui.sidebar.logged_in_as);
		hideMe(G.ui.sidebar.loginbox);
	}

	if(G.ui.sidebar.login) G.ui.sidebar.login.onclick = initLogin;
	if(G.ui.sidebar.logout) G.ui.sidebar.logout.onclick = doLogout; 
	G.ui.common.top_logo.setAttribute("src", buildImageLink(config.images.logo));
}

/* sets up the login ui components */
var loginBoxVisible = false;
function initLogin() {

	var loginDance = function() {
		if(doLogin()) {
			showCanvas();
			G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
			unHideMe(G.ui.sidebar.logoutbox);
			unHideMe(G.ui.sidebar.logged_in_as);
			hideMe(G.ui.sidebar.loginbox);
		}
	}

	G.ui.login.button.onclick = loginDance;
	G.ui.login.username.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) loginDance();};
	G.ui.login.password.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) loginDance();};

	if(loginBoxVisible) {
		showCanvas();
	} else {
		swapCanvas(G.ui.login.box);
		G.ui.login.username.focus();
	}

	loginBoxVisible = !loginBoxVisible;
	G.ui.login.cancel.onclick = showCanvas;
}

function setSidebarLinks() {
	G.ui.sidebar.home_link.setAttribute("href", buildOPACLink({page:HOME}));
	G.ui.sidebar.advanced_link.setAttribute("href", buildOPACLink({page:ADVANCED}));
	G.ui.sidebar.myopac_link.setAttribute("href", buildOPACLink({page:MYOPAC}, false, true));
}
