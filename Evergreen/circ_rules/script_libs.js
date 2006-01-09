/* pre-define all global circ vars.  This way, any vars not fetched and 
	defined by the circ code won't throw exceptions when accessed */

var hold				= null;	/* most recently retrieve hold object */
var copy				= null;	/* the current copy object */
var title			= null;	/* the current title (biblio record entry) object */
var patron			= null;	/* the current patron object */
var patron_info	= null;	/* additional info on the current patron */




/* Utility function ----------------------------------------------------- */

function is_true(item) { return !is_false(item); }

function is_false(item) { 
	if( ! item ) return true;
	if( item.match(/0/) ) return true;
	return false;
}

