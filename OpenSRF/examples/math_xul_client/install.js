// ripped from Evergreen installation file

/* We'll want to make this more flexible later */

install();

// ----------------------------------------------------------------------------
// Performs the install
// ----------------------------------------------------------------------------
function install() {

	// ----------------------------------------------------------------------------
	var _authors = "PINES";
	var _package = "math";
	var _packg_l = "math";
	var _version = "0.0.1";
	// ----------------------------------------------------------------------------

	var err; // track the error

	err = initInstall( _package, "/"+_authors+"/"+_package, _version );
	if( err != 0 ) { return warn( "initInstall: " + err );}

	// ----------------------------------------------------------------------------
	// Discovers the path to the install directory
	// ----------------------------------------------------------------------------
	install_dir = getFolder("Chrome", _packg_l );
	logComment( "Installing to: " + install_dir );

	// ----------------------------------------------------------------------------
	// Directory where the 'content' is stored
	// ----------------------------------------------------------------------------
	content_dir = getFolder( install_dir, "content" );
	if( err != 0 ) { return warn("getFolder:content_dir: " + err);}
	
	// ----------------------------------------------------------------------------
	// Directory where the skins are stored
	// ----------------------------------------------------------------------------
	skin_dir = getFolder( install_dir, "skin" );
	if( err != 0 ) { return warn("getFolder:skin: " + err);}

	// ----------------------------------------------------------------------------
	// Directory where the local data is stored
	// ----------------------------------------------------------------------------
	locale_dir = getFolder( install_dir, "locale" );
	if( err != 0 ) { return warn("getFolder:locale: " + err);}

	// ----------------------------------------------------------------------------
	// Sets the install directory for Evergreen
	// ----------------------------------------------------------------------------
	err = setPackageFolder(install_dir);
	if( err != 0 ) { return warn("setPackageFolder: " + err);}
	
	// ----------------------------------------------------------------------------
	// Searches the .xpi file for the directory name stored in _packg_l and
	// copies that directory from the .xpi into Mozilla's chrome directory.
	// In this case, we are copying over the entire evergreen folder
	// ----------------------------------------------------------------------------
	err = addDirectory( _packg_l )
	if( err != 0 ) { return warn("addDirectory: " + err);}
	

	// ----------------------------------------------------------------------------
	// Register the content directory
	// The final argument is where Mozilla should expect to find the contents.rdf 
	// file *after* installation for the CONTENT portion of the package
	// ----------------------------------------------------------------------------
	err = registerChrome( Install.CONTENT, content_dir );
	if( err != 0 ) { return warn("registerChrome:content  " + err );}
	
	// ----------------------------------------------------------------------------
	// Register the skin directory
	// ----------------------------------------------------------------------------
	err = registerChrome( Install.SKIN, skin_dir );
	if( err != 0 ) { return warn("registerChrome:skin " + err );}

	// ----------------------------------------------------------------------------
	// Register the locale directory 
	// ----------------------------------------------------------------------------
	//err = registerChrome( Install.LOCALE, locale_dir );
	//if( err != 0 ) { return warn("registerChrome:locale " + err );}

	err = registerChrome( Install.LOCALE, getFolder(locale_dir, "en-US") );
	if( err != 0 ) { return warn("registerChrome:locale " + err );}

	// ----------------------------------------------------------------------------
	// Do it.
	// ----------------------------------------------------------------------------
	performInstall();
	
}

function warn( message ) {
	alert( message );
	logComment( message );
	return;
}

