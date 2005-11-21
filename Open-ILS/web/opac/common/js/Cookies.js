// HTTP.Cookies - Burak Gürsoy <burak[at]cpan[dot]org>
if (!HTTP) var HTTP = {}; // create base class if undefined

HTTP.Cookies = function () { // HTTP.Cookies constructor
   this.JAR = ''; // data cache
}

HTTP.Cookies.VERSION = '1.01';

HTTP.Cookies.Date = function () { // expire time calculation class
   this.format = {
   's' : 1,
   'm' : 60,
   'h' : 60 * 60,
   'd' : 60 * 60 * 24,
   'M' : 60 * 60 * 24 * 30,
   'y' : 60 * 60 * 24 * 365
   };
}

HTTP.Cookies.Date.prototype.parse = function (x) {
   if(!x || x == 'now') return 0;
   var date = x.match(/^(.+?)(\w)$/i);
   var of = 0;
   return (this.is_num(date[1]) && (of = this.is_date(date[1],date[2]))) ? of : 0;
}

HTTP.Cookies.Date.prototype.is_date = function (num, x) {
   if (!x || x.length != 1) return 0;
   var ar = [];
   return (ar = x.match(/^(s|m|h|d|w|M|y)$/) ) ? num * 1000 * this.format[ar[0]] : 0;
}

HTTP.Cookies.Date.prototype.is_num = function (x) {
   if (x.length == 0) return;
   var ok = 1;
   for (var i = 0; i < x.length; i++) {
      if ("0123456789.-+".indexOf(x.charAt(i)) == -1) {
         ok--;
         break;
      }
   }
   return ok;
}

HTTP.Cookies.prototype.date = new HTTP.Cookies.Date; // date object instance

// Get the value of the named cookie. Usage: password = cookie.read('password');
HTTP.Cookies.prototype.read = function (name) {
   var value  = '';
   if(!this.JAR) {
		this.JAR = {};
      var array  = document.cookie.split(';');
      for (var x = 0; x < array.length; x++) {
         var pair = array[x].split('=');
         if(pair[0].substring (0,1) == ' ') pair[0] = pair[0].substring(1, pair[0].length);
         if(pair[0] == name) {
            value = pair[1];
         }
         this.JAR[pair[0]] = pair[1];
      }
   } else {
      for(var cookie in this.JAR) {
         if(cookie == name) {
            value = this.JAR[cookie];
         }
	   }
   }
   return value ? unescape(value) : '';
}

// Create a new cookie or overwrite existing. Usage: cookie.write('password', 'secret', '1m');
HTTP.Cookies.prototype.write = function (name, value, expires, path, domain, secure) {
   var extra = '';
   if (!expires) expires = '';
   if (expires == '_epoch') {
      expires = new Date(0);
   } else if (expires != -1) {
      var Now  = new Date;
      Now.setTime(Now.getTime() + this.date.parse(expires));
      expires = Now.toGMTString();
   }
   if(expires) extra += "; expires=" + expires;
   if(path   ) extra += "; path="    + path;
   if(domain ) extra += "; domain="  + domain;
   if(secure ) extra += "; secure="  + secure;
   document.cookie = name + "=" + escape(value) + extra;
}

// Delete the named cookie. Usage: cookie.remove('password');
HTTP.Cookies.prototype.remove = function (name, path, domain, secure) {
   this.write(name, '', '_epoch', path, domain, secure);
}

/*

=head1 NAME

HTTP.Cookies - JavaScript class for reading, writing and deleting cookies

=head1 SYNOPSIS

   var cookie    = new HTTP.Cookies;
   var password  = cookie.read('password');
   var lastvisit = cookie.read('lastvisit');
   cookie.write('lastvisit',1079383075,'+1y');
   cookie.remove('password');

=head1 DESCRIPTION

HTTP.Cookies is a class for http cookies manipulation. It defines
three object methods to read, write and remove cookies. Implementation
is somehow similar to the Perl module CGI.pm' s C<cookie()> method.

=head1 METHODS

=head2 read NAME

Reads the cookie named C<name> and returns it's value or an empty
string upon failure.

=head2 write NAME, VALUE [, EXPIRES, PATH, DOMAIN, SECURE]

Creates a new cookie with C<NAME> and C<VALUE>. Optional C<EXPIRES>
value sets the cookie lifetime.

Expire date format: you can use negative or positive numbers combined
with 's', 'm', 'h', 'd', 'w', 'M', 'y' or you can use 'now' to
expire as soon as possible. Meanings:

    s   = second
    m   = minute
    h   = hour
    d   = day
    w   = week
    M   = month
    y   = year
    now = immediately

for a session cookie; pass "-1" as the expires value.

Optional parameter C<DOMAIN> can be used to define the domain
for which the HTTP cookie is valid.

Optional parameter C<EXPIRES> can be used to make it a secure cookie
(secure cookies can only be used with HTTPS protocol).

=head2 remove NAME [, PATH, DOMAIN, SECURE]

Deletes/removes the named cookie from the client.

=head1 SEE ALSO

=head1 BUGS

Contact the author if you find any.

This library is tested with: Opera 8.01, MSIE 6.0,
Netscape Communicator 4.77, Mozilla 1.7.8
and Mozilla FireFox 1.0.4 under Windows XP Professional SP2.

=head1 AUTHOR

Burak Gürsoy, E<lt>burakE<64>cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2005 Burak Gürsoy. All rights reserved.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the terms of the "Artistic License":
L<http://dev.perl.org/licenses/artistic.html>.

=cut

*/
