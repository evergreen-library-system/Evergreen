dump('entering util/money.js\n');

if (typeof util == 'undefined') var util = {};
util.money = {};

util.money.EXPORT_OK	= [ 
	'sanitize', 'dollars_float_to_cents_integer', 'cents_as_dollars'
];
util.money.EXPORT_TAGS	= { ':all' : util.money.EXPORT_OK };

util.money.dollars_float_to_cents_integer = function( money ) {
	// careful to avoid fractions of pennies
	var money_s = money.toString();
	// FIXME: strip miscellaneous characters
	var marray = money_s.split(".");
	var dollars = marray[0];
	var cents = marray[1];
	try {
		if (cents.length < 2) {
			cents = cents + '0';
		}
	} catch(E) {
	}
	try {
		if (cents.length > 2) {
			dump("util.money: We don't round money\n");
			cents = cents.substr(0,2);
		}
	} catch(E) {
	}
	var total = 0;
	try {
		if (parseInt(cents)) total += parseInt(cents);
	} catch(E) {
	}
	try {
		if (parseInt(dollars)) total += (parseInt(dollars) * 100);
	} catch(E) {
	}
	return total;	
}

util.money.cents_as_dollars = function( cents ) {
	cents = cents.toString(); 
	// FIXME: strip miscellaneous characters
	if (cents.match(/\./)) cents = util.money.dollars_float_to_cents_integer( cents ).toString();
	try {
		switch( cents.length ) {
			case 0: cents = '000'; break;
			case 1: cents = '00' + cents; break;
		}
	} catch(E) {
	}
	return cents.substr(0,cents.length-2) + '.' + cents.substr(cents.length - 2);
}

util.money.sanitize = function( money ) {
	return util.money.cents_as_dollars( util.money.dollars_float_to_cents_integer( money ) );
}


dump('exiting util/money.js\n');
