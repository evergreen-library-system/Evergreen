/*  DepressedPress.com DP_DateExtensions
Author: Jim Davis, the Depressed Press of Boston
Date: June 20, 2006
Contact: webmaster@depressedpress.com
Website: www.depressedpress.com

Full documentation can be found at:
http://www.depressedpress.com/Content/Development/JavaScript/Extensions/

DP_DateExtensions adds features to the JavaScript "Date" datatype.
Copyright (c) 1996-2006, The Depressed Press of Boston (depressedpress.com)
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

+) Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer. 
+) Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution. 
+) Neither the name of the DEPRESSED PRESS OF BOSTON (DEPRESSEDPRESS.COM) nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission. 

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


CHANGES: --------------------------------------------------------------------------------

	2008-07-26 / dscott@laurentian.ca
	 - Comment out Date.parseIso8601 as we move to Dojo

    2007-02-02 / billserickson@gmail.com
     - chopped out some utility methods to trim file size
     - changed some formatting for visual ease
     - date / time can now be separated by a "T", "t" or a space
     - truncating milliseconds.  not needed and .123456  
        comes accross 123456ms and not 123ms + 456 microseconds
*/

/*
Date.parseIso8601 = function(CurDate) {

		// Check the input parameters
	if ( typeof CurDate != "string" ) {
		return null;
	};
		// Set the fragment expressions
	var S = "[\\-/:.]";
	var Yr = "((?:1[6-9]|[2-9][0-9])[0-9]{2})";
	var Mo = S + "((?:1[012])|(?:0[1-9])|[1-9])";
	var Dy = S + "((?:3[01])|(?:[12][0-9])|(?:0[1-9])|[1-9])";
	var Hr = "(2[0-4]|[01]?[0-9])";
	var Mn = S + "([0-5]?[0-9])";
	var Sd = "(?:" + S + "([0-5]?[0-9])(?:[.,]([0-9]+))?)?";
	var TZ = "(?:(Z)|(?:([\+\-])(1[012]|[0]?[0-9])(?::?([0-5]?[0-9]))?))?";
		// RegEx the input
		// First check: Just date parts (month and day are optional)
		// Second check: Full date plus time (seconds, milliseconds and TimeZone info are optional)
	var TF;

	if ( TF = new RegExp("^" + Yr + "(?:" + Mo + "(?:" + Dy + ")?)?" + "$").exec(CurDate) ) {
        } else if ( TF = new RegExp("^" + Yr + Mo + Dy + "[Tt ]" + Hr + Mn + Sd + TZ + "$").exec(CurDate) ) {};

		// If the date couldn't be parsed, return null
	if ( !TF ) { return null };
		// Default the Time Fragments if they're not present
	if ( !TF[2] ) { TF[2] = 1 } else { TF[2] = TF[2] - 1 };
	if ( !TF[3] ) { TF[3] = 1 };
	if ( !TF[4] ) { TF[4] = 0 };
	if ( !TF[5] ) { TF[5] = 0 };
	if ( !TF[6] ) { TF[6] = 0 };
	if ( !TF[7] ) { TF[7] = 0 };
	if ( !TF[8] ) { TF[8] = null };
	if ( TF[9] != "-" && TF[9] != "+" ) { TF[9] = null };
	if ( !TF[10] ) { TF[10] = 0 } else { TF[10] = TF[9] + TF[10] };
	if ( !TF[11] ) { TF[11] = 0 } else { TF[11] = TF[9] + TF[11] };
		// If there's no timezone info the data is local time

    TF[7] = 0;

	if ( !TF[8] && !TF[9] ) {
		return new Date(TF[1], TF[2], TF[3], TF[4], TF[5], TF[6], TF[7]);
	};
		// If the UTC indicator is set the date is UTC
	if ( TF[8] == "Z" ) {
		return new Date(Date.UTC(TF[1], TF[2], TF[3], TF[4], TF[5], TF[6], TF[7]));
	};
		// If the date has a timezone offset
	if ( TF[9] == "-" || TF[9] == "+" ) {
			// Get current Timezone information
		var CurTZ = new Date().getTimezoneOffset();
		var CurTZh = TF[10] - ((CurTZ >= 0 ? "-" : "+") + Math.floor(Math.abs(CurTZ) / 60))
		var CurTZm = TF[11] - ((CurTZ >= 0 ? "-" : "+") + (Math.abs(CurTZ) % 60))
			// Return the date
		return new Date(TF[1], TF[2], TF[3], TF[4] - CurTZh, TF[5] - CurTZm, TF[6], TF[7]);
	};
		// If we've reached here we couldn't deal with the input, return null
	return null;

};

*/


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */
/* "Date" Object Prototype Extensions */
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

Date.prototype.dateFormat = function(Mask) {

	var FormattedDate = "";
	var Ref_MonthFullName = ["January", "February", "March", "April", "May", 
        "June", "July", "August", "September", "October", "November", "December"];
	var Ref_MonthAbbreviation = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
	var Ref_DayFullName = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
	var Ref_DayAbbreviation = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

		// Convert any supported simple masks into "real" masks
	switch (Mask) {
		case "short":
			Mask = "m/d/yy";		
		break;
		case "medium":
			Mask = "mmm d, yyyy";
		break;
		case "long":
			Mask = "mmmm d, yyyy";
		break;
		case "full":
			Mask = "dddd, mmmm d, yyyy";
		break;
	};

		// Tack a temporary space at the end of the mask to ensure that the last character isn't a mask character
	Mask += " ";

		// Parse the Mask
	var CurChar;
	var MaskPart = "";
	for ( var Cnt = 0; Cnt < Mask.length; Cnt++ ) {
			// Get the character
		CurChar = Mask.charAt(Cnt);
			// Determine if the character is a mask element
		if ( (CurChar != "d") && (CurChar != "m") && (CurChar != "y") ) {
				// Determine if we need to parse a MaskPart or not
			if ( MaskPart != "" ) {
					// Convert the mask part to the date value
				switch (MaskPart) {
					case "d":
						FormattedDate += this.getDate();
						break;
					case "dd":
						FormattedDate += ("0" + this.getDate()).slice(-2);
						break;
					case "ddd":
						FormattedDate += Ref_DayAbbreviation[this.getDay()];
						break;
					case "dddd":
						FormattedDate += Ref_DayFullName[this.getDay()];
						break;
					case "m":
						FormattedDate += this.getMonth() + 1;
						break;
					case "mm":
						FormattedDate += ("0" + (this.getMonth() + 1)).slice(-2);
						break;
					case "mmm":
						FormattedDate += Ref_MonthAbbreviation[this.getMonth()];
						break;
					case "mmmm":
						FormattedDate += Ref_MonthFullName[this.getMonth()];
						break;
					case "yy":
						FormattedDate += ("0" + this.getFullYear()).slice(-2);
						break;
					case "yyyy":
						FormattedDate += ("000" + this.getFullYear()).slice(-4);
						break;
				};
					// Reset the MaskPart to nothing
				MaskPart = "";
			};
				// Add the character to the output
			FormattedDate += CurChar;
		} else {
				// Add the current mask character to the MaskPart
			MaskPart += CurChar;
		};
	};

		// Remove the temporary space from the end of the formatted date
	FormattedDate = FormattedDate.substring(0,FormattedDate.length - 1);

		// Return the formatted date
	return FormattedDate;

};


Date.prototype.timeFormat = function(Mask) {

	var FormattedTime = "";

		// Convert any supported simple masks into "real" masks
	switch (Mask) {
		case "short":
			Mask = "h:mm tt";		
		break;
		case "medium":
			Mask = "h:mm:ss tt";
		break;
		case "long":
			Mask = "h:mm:ss.l tt";
		break;
		case "full":
			Mask = "h:mm:ss.l tt";
		break;
	};

		// Tack a temporary space at the end of the mask to ensure that the last character isn't a mask character
	Mask += " ";

		// Parse the Mask
	var CurChar;
	var MaskPart = "";
	for ( var Cnt = 0; Cnt < Mask.length; Cnt++ ) {
			// Get the character
		CurChar = Mask.charAt(Cnt);
			// Determine if the character is a mask element
		if ( (CurChar != "h") && (CurChar != "H") && (CurChar != "m") && 
            (CurChar != "s") && (CurChar != "l") && (CurChar != "t") && (CurChar != "T") ) {
				// Determine if we need to parse a MaskPart or not
			if ( MaskPart != "" ) {
					// Convert the mask part to the date value
				switch (MaskPart) {
					case "h":
						var CurValue = this.getHours();
						if ( CurValue >  12 ) {
							CurValue = CurValue - 12;
						};
						FormattedTime += CurValue;
						break;
					case "hh":
						var CurValue = this.getHours();
						if ( CurValue >  12 ) {
							CurValue = CurValue - 12;
						};
						FormattedTime += ("0" + CurValue).slice(-2);
						break;
					case "H":
						FormattedTime += ("0" + this.getHours()).slice(-2);
						break;
					case "HH":
						FormattedTime += ("0" + this.getHours()).slice(-2);
						break;
					case "m":
						FormattedTime += this.getMinutes();
						break;
					case "mm":
						FormattedTime += ("0" + this.getMinutes()).slice(-2);
						break;
					case "s":
						FormattedTime += this.getSeconds();
						break;
					case "ss":
						FormattedTime += ("0" + this.getSeconds()).slice(-2);
						break;
					case "l":
						FormattedTime += ("00" + this.getMilliseconds()).slice(-3);
						break;
					case "t":
						if ( this.getHours() > 12 ) {
							FormattedTime += "p";
						} else {
							FormattedTime += "a";
						};
						break;
					case "tt":
						if ( this.getHours() > 12 ) {
							FormattedTime += "pm";
						} else {
							FormattedTime += "am";
						};
						break;
					case "T":
						if ( this.getHours() > 12 ) {
							FormattedTime += "P";
						} else {
							FormattedTime += "A";
						};
						break;
					case "TT":
						if ( this.getHours() > 12 ) {
							FormattedTime += "PM";
						} else {
							FormattedTime += "AM";
						};
						break;
				};
					// Reset the MaskPart to nothing
				MaskPart = "";
			};
				// Add the character to the output
			FormattedTime += CurChar;
		} else {
				// Add the current mask character to the MaskPart
			MaskPart += CurChar;
		};
	};

		// Remove the temporary space from the end of the formatted date
	FormattedTime = FormattedTime.substring(0,FormattedTime.length - 1);

		// Return the formatted date
	return FormattedTime;

};


/*
    dropTZ - do not include the timezone in the output.  only used for YMDH+
    useSpace - if true, use a space instaed of a "T" between date and time
*/
Date.prototype.iso8601Format = function(Style, isUTC, dropTZ, useSpace) {

	var FormattedDate = "";

	switch (Style) {
		case "Y":
			FormattedDate += this.dateFormat("yyyy");
			break;
		case "YM":
			FormattedDate += this.dateFormat("yyyy-mm");
			break;
		case "YMD":
			FormattedDate += this.dateFormat("yyyy-mm-dd");
			break;
		case "YMDHM":
			FormattedDate += this.dateFormat("yyyy-mm-dd") + ((useSpace) ? " " : "T") + this.timeFormat("HH:mm");
			break;
		case "YMDHMS":
			FormattedDate += this.dateFormat("yyyy-mm-dd") + ((useSpace) ? " " : "T") + this.timeFormat("HH:mm:ss");
			break;
		case "YMDHMSM":
			FormattedDate += this.dateFormat("yyyy-mm-dd") + ((useSpace) ? " " : "T") + this.timeFormat("HH:mm:ss.l");
			break;
	};

	if ( !dropTZ && (Style == "YMDHM" || Style == "YMDHMS" || Style == "YMDHMSM") ) {
		if ( isUTC ) {
			FormattedDate += "Z";
		} else {
				// Get TimeZone Information
			var TimeZoneOffset = this.getTimezoneOffset();
			var TimeZoneInfo = (TimeZoneOffset >= 0 ? "-" : "+") + 
                ("0" + (Math.floor(Math.abs(TimeZoneOffset) / 60))).slice(-2) + ":" + 
                ("00" + (Math.abs(TimeZoneOffset) % 60)).slice(-2);
			FormattedDate += TimeZoneInfo;
		};
	};	

		// Return the date
	return FormattedDate;

};




