sdump('D_TRACE',"Loading validate.js\n");

function valid_year_month_day(year,month,day) {
	var date = new Date(year,month-1,day);
	return (
		(date.getFullYear() == year) &&
		(date.getMonth()+1 == month) &&
		(date.getDate() == day)
	);
}

function textbox_checkdigit(ev) {
	if ( check_checkdigit( ev.target.value ) ) {
		sdump('D_VALIDATE', 'success\n');
		return true;
	} else {
		sdump('D_VALIDATE', 'failure\n');
		ev.preventDefault();
		ev.stopPropagation();
		return false;
	}
}

function check_checkdigit(barcode) {

	var stripped_barcode = barcode.slice(0,-1);
	var checkdigit = barcode.slice(-1);

	sdump('D_VALIDATE', '\n\n=-=***=-=\n\ncheck_checkdigit: barcode = ' + barcode + ' barcode stripped = ' + stripped_barcode + ' checkdigit = ' + checkdigit + '\n');

	var sum = 0; var mul = 2;

	var b_array = string_to_array( stripped_barcode ).reverse();
	sdump('D_VALIDATE', '\tb_array = ' + b_array + '\n');

	for (var i in b_array) {
		var digit = parseInt( b_array[i] );
		sdump('D_VALIDATE', '\t\tdigit = ' + digit + '\n');

		var product = digit * mul;
		if (mul == 2) { mul = 1; } else { mul = 2; }

		var p_array = string_to_array( product.toString() );
		sdump('D_VALIDATE', '\t\tp_array = ' + p_array + '\n');

		for (var j in p_array) { 
			var n = parseInt( p_array[j] );
			sdump('D_VALIDATE', '\t\t\tn = ' + n + '\n');
			sum += n;
		}
	}

	sdump('D_VALIDATE', '\tsum = ' + sum + '\n');

	var s_array = string_to_array( sum.toString() );
	var calculated_checkdigit = s_array.pop();
	if (calculated_checkdigit > 0) calculated_checkdigit = 10 - calculated_checkdigit;
	sdump('D_VALIDATE', '\tcalculated checkdigit = ' + calculated_checkdigit + '\n\n=-=***=-=\n\n');

	return ( calculated_checkdigit == checkdigit );
}


