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
if (arguments.length > 3) { // field name(s) specified
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
if (i >=0) {
  this.fields[i] = fieldval
  return true
} else {
  return false
}
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

// concatenate array elements into cookie string

// Special case - single-field cookie, so write without # terminator
if (this.fields.length == 1) {
  cookietext += escape(this.fields[0])
  } else { // multi-field cookie
    for (i= 0; i < this.fields.length; i++) {
      cookietext += escape(this.fields[i]) + this.fieldSeparator }
  }


// Set expiry parameter, if specified
    if (this.expires != null) {  
      if (typeof(this.expires) == "number") { // Expiry period in days specified  
        var today=new Date()     
        var expiredate = new Date()      
        expiredate.setTime(today.getTime() + 1000*60*60*24*this.expires)
        cookietext += "; expires=" + expiredate.toGMTString()
      } else { // assume it's a date object
        cookietext +=  "; expires=" + this.expires.toGMTString()
      } // end of typeof(this.expires) if
    } // end of this.expires != null if 
   
// add path, if specified
   if (this.accessPath != null) {
   cookietext += "; PATH="+this.accessPath }

// write cookie
   // alert("writing "+cookietext)
   document.cookie = cookietext 
   return null  
}


function ucRead() {
  var search = this.name + "="                       
  var CookieString = document.cookie            
  this.rawValue = null
  this.found = false     
  if (CookieString.length > 0) {                
    offset = CookieString.indexOf(search)       
    if (offset != -1) {                         
      offset += search.length                   
      end = CookieString.indexOf(";", offset)   
      if (end == -1) {  // cookie is last item in the string, so no terminator                        
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

// Special case - single-field cookies written by other functions,
// so without a '#' terminator

if (this.rawValue.substr(sl-1, 1) != this.fieldSeparator) {
  this.fields[0] = unescape(this.rawValue)
  } else { // separate fields

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
} // end of unpack into fields if block
  return this.found
} // end of function


function ucDelete() {
  this.expires = -10
  this.write()
  return this.read()
}



/*
*********** IT'S OK TO REMOVE THE CODE BELOW HERE IF YOUR PAGE 
DOESN'T USE cookieList() OBJECTS OR THE findCookieObject() FUNCTION.
*/




function findCookieObject(cName, cObjArray) {
/* 
This function finds a named cookie among the objects
pointed to by a cookieList array (see below).

Parameters are the cookie name to search for (a string), and an array created with 
the new cookieList() constructor (see below)

NOTE - if you're only dealing with a specific, named cookie, then it's
more efficient to ceate a single cookieObject directly with that name,
and check its .found property to see if it already exists on this client.

This function is for when you've created an all-cookies array anyway,
and now want to check whether a specific cookie is present.

It returns a pointer to the cookieObject if found, or null if not found.
*/

var cpointer = null, i
for (i in cObjArray) {
  if (cName == cObjArray[i].name) {
    cpointer = cObjArray[i]
  }
}
return cpointer
}


function cookieList() {
/* 
This constructor function creates a cookieObject object (see below) 
for each cookie in document.cookie,
and returns an array of pointers to the objects.

You can use it to load all the cookies available to a page, then walk through them.

Example usage:

cookList = new cookieList()
for (i in cookList) {
 document.write(cookList[i].name + " " + cookList[i].fields[0] + "
")
}

*/

var i = 0, rawstring, offset = 0, start, newname
cpointers = new Array()
rawstring = document.cookie
if (rawstring.length > 0) {
  do {
   start = rawstring.indexOf("=", offset)
   if (start != -1) { // another cookie found in string
     // get cookie string up to end of current cookie name
     newname = rawstring.substring(0, start) 
     if (offset > 0) { 
       // if not first cookie in string, remove previous cookie data from substring
       // subsequent cookie names have a space before them (just a little browser foible!)
       newname = newname.substring(newname.lastIndexOf(";")+2, start)
     }     
     cpointers[i] = new cookieObject(newname)
     offset = start + 1
     i++
   }
  } while (start != -1)
} // end rawstring.length > 0
return cpointers
} //end function

