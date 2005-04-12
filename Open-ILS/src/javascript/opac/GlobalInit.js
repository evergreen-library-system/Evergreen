/* */

var globalPage = null;

function globalInit() {

	var page_name = globalPageTarget;

	if(!page_name) 
		throw new EXArg("globalInit requires globalPageTarget to be set");

	debug("globalInit init-ing page: " + page_name );

	switch( page_name ) {

		case "start":
			globalPage = new OPACStartPage();
			break;

		case  "advanced_search":
			globalPage = new AdvancedSearchPage();
			break;

		case  "mr_result":
			globalPage = new MRResultPage();
			break;

		case  "record_result":
			globalPage = new RecordResultPage();
			break;

		case  "login":
			globalPage = new LoginPage();
			break;

		case  "logout":
			globalPage = new LogoutPage();
			break;

		case  "my_opac":
			globalPage = new MyOPACPage();
			break;

		case  "about":
			globalPage = new AboutPage();
			break;

		}

	if( ! globalPage ) 
		throw new EXArg(
				"globalInit requires a valid page target: " + page_name );

	globalPage.init();

}


