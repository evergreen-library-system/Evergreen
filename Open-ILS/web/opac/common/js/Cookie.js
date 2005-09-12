/*
DISCLAIMER: THESE JAVASCRIPT FUNCTIONS ARE SUPPLIED 'AS IS', WITH 
NO WARRANTY EXPRESSED OR IMPLIED. YOU USE THEM AT YOUR OWN RISK. 
PAUL STEPHENS DOES NOT ACCEPT ANY LIABILITY FOR 
ANY LOSS OR DAMAGE RESULTING FROM THEIR USE, HOWEVER CAUSED. 

Paul Stephens' cookie-handling object library

Version 2.1
2.0 - Introduces field names
2.1 - Fixes bug where undefined embedded fields[] elements weren't written to disk

www.paulspages.co.uk 

TO USE THIS LIBRARY, INSERT ITS CONTENTS IN THE <HEAD> SECTION 
OF YOUR WEB PAGE SOURCE, BEFORE ANY OTHER JAVASCRIPT ROUTINES.

(C) Paul Stephens, 2001-2003. Feel free to use this code, but please leave this comment block in. This code must not be sold, either alone or as part of an application, without the consent of the author.
*/

function cookieObject(name, expires, accessPath) {
var i, j
this.name = name
this.fieldSeparator = "#"
this.found = false
this.expires = expires
this.accessPath = accessPath
this.rawValue = ""
this.fields = new Array()
this.fieldnames = new Array() 
if (arguments.length > 3) { 
  j = 0
  for (i = 3; i < arguments.length; i++) {
    this.fieldnames[j] = arguments[i]    
    j++
  }
  this.fields.length = this.fieldnames.length 
}
this.read = ucRead
this.write = ucWrite
this.remove = ucDelete
this.get = ucFieldGet
this.put = ucFieldPut
this.namepos = ucNamePos
this.read()
}

function ucFieldGet(fieldname) {
var i = this.namepos(fieldname)
if (i >=0) {
  return this.fields[i]
} else {
  return "BadFieldName!"
}
}
function ucFieldPut (fieldname, fieldval) {
var i = this.namepos(fieldname)
if(i < 0) {
	i = this.fieldnames.length;
	this.fieldnames[i] = fieldname;
}
this.fields[i] = fieldval
return true
}
function ucNamePos(fieldname) {
var i 
for (i = 0; i < this.fieldnames.length; i++) {
  if (fieldname == this.fieldnames[i]) {
    return i
  }
}
return -1
}
function ucWrite() {      
  var cookietext = this.name + "=" 
if (this.fields.length == 1) {
  cookietext += escape(this.fields[0])
  } else { 
    for (i= 0; i < this.fields.length; i++) {
      cookietext += escape(this.fields[i]) + this.fieldSeparator }
  }
    if (this.expires != null) {  
      if (typeof(this.expires) == "number") { 
        var today=new Date()     
        var expiredate = new Date()      
        expiredate.setTime(today.getTime() + 1000*60*60*24*this.expires)
        cookietext += "; expires=" + expiredate.toGMTString()
      } else { 
        cookietext +=  "; expires=" + this.expires.toGMTString()
      } 
    } 
   if (this.accessPath != null) {
   cookietext += "; PATH="+this.accessPath }
   document.cookie = cookietext 
   return null  
}
function ucRead() {
  var search = this.name + "="                       
  var CookieString = document.cookie            
  if(CookieString == null) CookieString = "";
  this.rawValue = null
  this.found = false     
  if (CookieString.length > 0) {                
    offset = CookieString.indexOf(search)       
    if (offset != -1) {                         
      offset += search.length                   
      end = CookieString.indexOf(";", offset)   
      if (end == -1) {  
       end = CookieString.length }              
      this.rawValue = CookieString.substring(offset, end)                                   
      this.found = true 
      } 
    }
if (this.rawValue != null) { // unpack into fields
  var sl = this.rawValue.length
  var startidx = 0
  var endidx = 0
  var i = 0
if (this.rawValue.substr(sl-1, 1) != this.fieldSeparator) {
  this.fields[0] = unescape(this.rawValue)
  } else { 
  do  
  {
   endidx = this.rawValue.indexOf(this.fieldSeparator, startidx)
   if (endidx !=-1) {
     this.fields[i] = unescape(this.rawValue.substring(startidx, endidx))
     i++
     startidx = endidx + 1}
  }
  while (endidx !=-1 & endidx != (this.rawValue.length -1));
}
} 
  return this.found
} 
function ucDelete() {
  this.expires = -10
  this.write()
  return this.read()
}
