// Date/W3CDTF.js -- W3C Date and Time Formats

Date.W3CDTF = function ( dtf ) {
    var dd = new Date();
    dd.setW3CDTF = Date.W3CDTF.prototype.setW3CDTF;
    dd.getW3CDTF = Date.W3CDTF.prototype.getW3CDTF;
    if ( dtf ) this.setW3CDTF( dtf );
    return dd;
};

Date.W3CDTF.VERSION = "0.03";

Date.W3CDTF.prototype.setW3CDTF = function( dtf ) {
    var sp = dtf.split( /[^0-9]/ );

    // invalid format
    if ( sp.length < 6 || sp.length > 8 ) return;

    // invalid time zone
    if ( sp.length == 7 ) {
        if ( dtf.charAt( dtf.length-1 ) != "Z" ) return;
    }

    // to numeric
    for( var i=0; i<sp.length; i++ ) sp[i] = sp[i]-0;

    // invalid range
    if ( sp[0] < 1970 ||                // year
         sp[1] < 1 || sp[1] > 12 ||     // month
         sp[2] < 1 || sp[2] > 31 ||     // day
         sp[3] < 0 || sp[3] > 23 ||     // hour
         sp[4] < 0 || sp[4] > 59 ||     // min
         sp[5] < 0 || sp[5] > 60 ) {    // sec
        return;                         // invalid date 
    }

    // get UTC milli-second

    var msec = Date.UTC( sp[0], sp[1]-1, sp[2], sp[3], sp[4], sp[5] );

    // time zene offset
    if ( sp.length == 8 ) {
        if ( dtf.indexOf("+") < 0 ) sp[6] *= -1;
        if ( sp[6] < -12 || sp[6] > 13 ) return;    // time zone offset hour
        if ( sp[7] < 0 || sp[7] > 59 ) return;      // time zone offset min
        msec -= (sp[6]*60+sp[7]) * 60000;
    }

    // set by milli-second;
    return this.setTime( msec );
};

Date.W3CDTF.prototype.getW3CDTF = function() {
    var year = this.getFullYear();
    var mon  = this.getMonth()+1;
    var day  = this.getDate();
    var hour = this.getHours();
    var min  = this.getMinutes();
    var sec  = this.getSeconds();

    // time zone
    var tzos = this.getTimezoneOffset();
    var tzpm = ( tzos > 0 ) ? "-" : "+";
    if ( tzos < 0 ) tzos *= -1;
    var tzhour = tzos / 60;
    var tzmin  = tzos % 60;

    // sprintf( "%02d", ... )
    if ( mon  < 10 ) mon  = "0"+mon;
    if ( day  < 10 ) day  = "0"+day;
    if ( hour < 10 ) hour = "0"+hour;
    if ( min  < 10 ) min  = "0"+min;
    if ( sec  < 10 ) sec  = "0"+sec;
    if ( tzhour < 10 ) tzhour = "0"+tzhour;
    if ( tzmin  < 10 ) tzmin  = "0"+tzmin;
    var dtf = year+"-"+mon+"-"+day+"T"+hour+":"+min+":"+sec+tzpm+tzhour+":"+tzmin;
    return dtf;
};

/*

=head1 NAME

Date.W3CDTF - W3C Date and Time Formats

=head1 SYNOPSIS

    var dd = new Date.W3CDTF();         // now
    document.write( "getW3CDTF: "+ dd.getW3CDTF() +"\n" );

    dd.setW3CDTF( "2005-04-23T17:20:00+09:00" );
    document.write( "toLocaleString: "+ dd.toLocaleString() +"\n" );

=head1 DESCRIPTION

This module understands the W3CDTF date/time format, an ISO 8601 profile, 
defined by W3C. This format as the native date format of RSS 1.0.
It can be used to parse these formats in order to create the appropriate objects.

=head1 METHODS

=head2 new()

This constructor method creates a new Date object which has 
following methods in addition to Date's all native methods.

=head2 setW3CDTF( "2006-02-15T19:40:00Z" )

This method parse a W3CDTF datetime string and sets it.

=head2 getW3CDTF()

This method returns a W3CDTF datetime string.
Its timezone is always local timezone configured on OS.

=head1 SEE ALSO

http://www.w3.org/TR/NOTE-datetime

=head1 AUTHOR

Yusuke Kawasaki http://www.kawa.net/

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2005-2006 Yusuke Kawasaki. All rights reserved.
This program is free software; you can redistribute it and/or 
modify it under the Artistic license. Or whatever license I choose,
which I will do instead of keeping this documentation like it is.

=cut
*/
