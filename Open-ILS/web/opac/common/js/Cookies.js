// HTTP.Cookies - Burak Gürsoy <burak[at]cpan[dot]org>

/*
I removed all the docs (except author and license info) to reduce download size
-bill erickson <billserickson@gmail.com>
*/

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
