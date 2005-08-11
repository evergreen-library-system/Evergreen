var timer = {};

function timer_init(id) {
	timer[id] = (new Date).getTime();
}

function timer_elapsed(id) {
	if (! timer[id]) { timer_init(id); }
	var ms = (new Date).getTime() - timer[id];
	return( ms + 'ms (' + ms/1000 + 's)' );
}

function db_date2Date(date) {
	var y  = date.substr(0,4);
	var mo = date.substr(5,2);
	var d  = date.substr(8,2);
	var h  = date.substr(11,2);
	var mi = date.substr(14,2);
	var s  = date.substr(17,2);
	return new Date(y,mo,d,h,mi,s);
}

function formatted_date(date,format) {
	// pass in a Date object or epoch seconds or a postgres style date string (2005-07-19 10:38:25.211964-04)
	if (typeof(date) == 'string') {
		if (date.match(/:/) || date.match(/-/)) {
			date = db_date2Date(date);
		} else {
			date = new Date( parseInt( date + '000' ) );
		}
	}
	var mm = date.getMonth() + 1; mm = mm.toString(); if (mm.length == 1) mm = '0' +mm;
	var dd = date.getDate().toString(); if (dd.length == 1) dd = '0' +dd;
	var yyyy = date.getFullYear().toString();
	var yy = yyyy.substr(2);
	var H = date.getHours(); H = H.toString(); if (H.length == 1) H = '0' + H;
	var I = date.getHours(); if (I > 12) I -= 12; I = I.toString();
	var M = date.getMinutes(); M = M.toString(); if (M.length == 1) M = '0' + M;
	var s = format;
	s = s.replace( /%m/g, mm );
	s = s.replace( /%d/g, dd );
	s = s.replace( /%Y/g, yyyy );
	s = s.replace( /%D/g, mm + '/' + dd + '/' + yy );
	s = s.replace( /%F/g, yyyy + '-' + mm + '-' + dd );
	s = s.replace( /%H/g, H );
	s = s.replace( /%I/g, I );
	s = s.replace( /%M/g, M );
	return s;
}

function interval_to_seconds ( $interval ) {

        $interval = $interval.replace( /and/, ',' );
        $interval = $interval.replace( /,/, ' ' );

        var $amount = 0;
	var results = $interval.match( /\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/g);  
	for (var i in results) {
		var result = results[i].match( /\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/ );
		if (result[2] == 's') $amount += result[1] ;
		if (result[2] == 'm') $amount += 60 * result[1] ;
		if (result[2] == 'h') $amount += 60 * 60 * result[1] ;
		if (result[2] == 'd') $amount += 60 * 60 * 24 * result[1] ;
		if (result[2] == 'w') $amount += 60 * 60 * 24 * 7 * result[1] ;
		if (result[2] == 'M') $amount += ((60 * 60 * 24 * 365)/12) * result[1] ;
		if (result[2] == 'y') $amount += 60 * 60 * 24 * 365 * result[1] ;
        }
        return $amount;
}


