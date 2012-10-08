dump('entering util/date.js\n');

if (typeof util == 'undefined') var util = {};
util.date = {};

util.date.EXPORT_OK    = [ 
    'check', 'check_past', 'timer_init', 'timer_elapsed', 'db_date2Date', 'formatted_date', 'interval_to_seconds'
];
util.date.EXPORT_TAGS    = { ':all' : util.date.EXPORT_OK };

util.date.check = function(format,date) {
    if (format != 'YYYY-MM-DD') { throw('I only understand YYYY-MM-DD.  Fix me if you want.'); }
    if (date.length != format.length) { return false; }
    if ((date.substr(4,1) != '-') || (date.substr(7,1) != '-')) { return false; }
    var yyyy = date.substr(0,4); var mm = date.substr(5,2); var dd = date.substr(8,2);
    var d = new Date( yyyy, mm - 1, dd );
    if (d.toString() == 'Invalid Date') { return false; }
    if (d.getMonth() != mm -1) { return false; }
    if (d.getFullYear() != yyyy) { return false; }
    if (dd.substr(0,1)=='0') { dd = dd.substr(1,1); }
    if (d.getDate() != dd) { return false; }
    return true;
}

util.date.check_past = function(format,date) {
    if (format != 'YYYY-MM-DD') { throw('I only understand YYYY-MM-DD.  Fix me if you want.'); }
    var yyyy = date.substr(0,4);
    var mm = date.substr(5,2);
    var dd = date.substr(8,2);
    var test_date = new Date( yyyy, mm - 1, dd );

    /* Ensure our date is valid */
    if (isNaN(test_date.getTime())) {
        throw('The date "' + date + '" is not valid.');
    }

    date = util.date.formatted_date(new Date(),'%F');
    yyyy = date.substr(0,4); mm = date.substr(5,2); dd = date.substr(8,2);
    var today = new Date( yyyy, mm - 1, dd );
    return test_date < today;
}

util.date.timer_init = function (id) {
    if (typeof util.date.timer_init.prototype.timer == 'undefined') {
        util.date.timer_init.prototype.timer = {};
    }
    util.date.timer_init.prototype.timer[id] = (new Date).getTime();
}

util.date.timer_elapsed = function (id) {
    if (! util.date.timer_init.prototype.timer[id]) { util.date.timer_init(id); }
    var ms = (new Date).getTime() - util.date.timer_init.prototype.timer[id];
    return( ms + 'ms (' + ms/1000 + 's)' );
}

util.date.db_date2Date = function (db_date) {
    if (!db_date) {  /* we get stringified null at times */
        return new Date(-8640000000000000); /* minimum possible date.
                                           max is this * -1. */
    } else if (typeof window.dojo != 'undefined') {
        dojo.require('dojo.date.stamp');
        return dojo.date.stamp.fromISOString( db_date.replace( /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[\+-]\d{2})(\d{2})$/, '$1:$2') );
    } else {
        var y  = db_date.substr(0,4); 
        var mo = db_date.substr(5,2); 
        var d  = db_date.substr(8,2); 
        var h  = db_date.substr(11,2); 
        var mi = db_date.substr(14,2); 
        var s  = db_date.substr(17,2); 
        return new Date(y,mo-1,d,h,mi,s); 
    }
}

util.date.formatted_date = function (orig_date,format) {

    var _date = orig_date;

    try { 

    // pass in a Date object or epoch seconds or a postgres style date string (2005-07-19 10:38:25.211964-04)
    if (typeof(_date) == 'string') {
        if (_date.match(/:/) || _date.match(/-/)) {
            _date = util.date.db_date2Date(_date);
        } else {
            _date = new Date( Number( _date + '000' ) );
        }
    } else if (typeof(_date) == 'number') {
        _date = new Date( _date * 1000 );
    } 
    
    if (_date == null) {
        return '';
    }

    var mm = _date.getMonth() + 1; mm = mm.toString(); if (mm.length == 1) mm = '0' +mm;
    var dd = _date.getDate().toString(); if (dd.length == 1) dd = '0' +dd;
    var yyyy = _date.getFullYear().toString();
    var yy = yyyy.substr(2);
    var H = _date.getHours(); H = H.toString(); if (H.length == 1) H = '0' + H;
    var I = _date.getHours(); if (I > 12) I -= 12; I = I.toString();
    var M = _date.getMinutes(); M = M.toString(); if (M.length == 1) M = '0' + M;
    var sec = _date.getSeconds(); sec = sec.toString(); if (sec.length == 1) sec = '0' + sec;

    var s = format;
    if (s == '') { s = '%F %H:%M'; }
    if (typeof window.dojo != 'undefined') {
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
        dojo.require('dojo.date.locale');
        dojo.require('dojo.date.stamp');
        var dojo_format = {};
        var dojo_format2 = { 'selector' : 'date' };
        if (data.hash.aous['format.date']) {
            dojo_format['datePattern'] = data.hash.aous['format.date'];
            dojo_format2['datePattern'] = data.hash.aous['format.date'];
        }
        if (data.hash.aous['format.time']) {
            dojo_format['timePattern'] = data.hash.aous['format.time'];
            dojo_format2['timePattern'] = data.hash.aous['format.time'];
        }
        s = s.replace( /%\{localized\}/g, dojo.date.locale.format( _date, dojo_format ) );
        s = s.replace( /%\{localized_date\}/g, dojo.date.locale.format( _date, dojo_format2 ) );
        s = s.replace( /%\{iso8601\}/g, dojo.date.stamp.toISOString( _date ) );
    }
    s = s.replace( /%m/g, mm );
    s = s.replace( /%d/g, dd );
    s = s.replace( /%Y/g, yyyy );
    s = s.replace( /%D/g, mm + '/' + dd + '/' + yy );
    s = s.replace( /%F/g, yyyy + '-' + mm + '-' + dd );
    s = s.replace( /%H/g, H );
    s = s.replace( /%I/g, I );
    s = s.replace( /%M/g, M );
    s = s.replace( /%s/g, sec );
    return s;

    } catch(E) {
        alert('Error in util.date.formatted_date:\nlocation.href = ' + location.href + '\ntypeof orig_date = ' + typeof orig_date + ' orig_date = ' + orig_date + '\ntypeof _date = ' + typeof _date + ' _date = ' + _date + '\nformat = ' + format + '\n' + E);
    }
}

util.date.interval_to_seconds = function ( $interval ) {

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

/* 
    Lifted from /opac/common/js/util.js

    builds a JS date object with the given info.  The given data
    has to be valid (e.g. months == 30 is not valid).  Returns NULL on 
    invalid date 
    Months are 1-12 (unlike the JS date object)
*/

util.date.buildDate = function ( year, month, day, hours, minutes, seconds ) {

    if(!year) year = 0;
    if(!month) month = 1;
    if(!day) day = 1;
    if(!hours) hours = 0;
    if(!minutes) minutes = 0;
    if(!seconds) seconds = 0;

    var d = new Date(year, month - 1, day, hours, minutes, seconds);
    //alert('util.date.buildDate\nyear='+year+' month='+month+' day='+day+' hours='+hours+' minutes='+minutes+' seconds='+seconds+'\nd = ' + d);
    
    if( 
        (d.getYear() + 1900) == year &&
        d.getMonth()    == (month - 1) &&
        d.getDate()        == new Number(day) &&
        d.getHours()    == new Number(hours) &&
        d.getMinutes() == new Number(minutes) &&
        d.getSeconds() == new Number(seconds) ) {
        return d;
    }

    return null;
}


dump('exiting util/date.js\n');
