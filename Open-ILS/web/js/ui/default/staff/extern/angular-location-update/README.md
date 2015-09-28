# angular-location-update

Updates location path without reloading of controller

## Install

1 `bower install angular-location-update --save` or [download](http://anglibs.github.io/angular-location-update/angular-location-update.min.js) or include hosted from github.io
````
    <script src="//anglibs.github.io/angular-location-update/angular-location-update.min.js"></script>
````

2 Add module to your app:
````
  angular.module('your_app', ['ngLocationUpdate']);
````

## Usage

````
$location.update_path('/notes/1');
$location.update_path('/notes/1/wysiwyg', true);
````
Parameters:
 1. New path
 1. Keep old path in browser history (By default it will be **replaced** by new one)

## When it's needed?

For example you have route `/notes/new` which shows form for new note.

In modern web app you may have no "Save" button - note created and saved to database once user made any change.
Then you would like to change route to `/notes/1` showing to user, that here is URL of his new document.
Also if he will refresh page or go back and forward using browser buttons - he will see what he expects.

## FYI

Did you know, that you can easily change your URLs  

from `http://mysite.com/#/notes/1` to `http://mysite.com/notes/1`

For this: 
 1. Config app: `angular.module('your_app').config(function($locationProvider) { $locationProvider.html5Mode(true); });`
 2. Add in your HTML `<base href="/">`

More info: https://docs.angularjs.org/guide/$location 

## Credits

Solution invented by guys in these threads:
 1. https://github.com/angular/angular.js/issues/1699
 1. https://github.com/angular-ui/ui-router/issues/427
 1. http://stackoverflow.com/questions/14974271/can-you-change-a-path-without-reloading-the-controller-in-angularjs
