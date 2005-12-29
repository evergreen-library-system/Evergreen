/**
* This function should return a URL which points to the book cover image based on ISBN.
* Ideally, this should point to some type of added content service.
* The example below uses Amazon... *use at own risk*
*/
function buildISBNSrc(isbn) {
	return "http://images.amazon.com/images/P/" + isbn + ".01._SCMZZZZZZZ_.jpg";
}      
