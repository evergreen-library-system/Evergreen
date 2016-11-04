
/**
 * egCoreMod houses all of the services, etc. required by all pages
 * for basic functionality.
 */
angular.module('egCoreMod', ['cfp.hotkeys', 'ngFileSaver', 'ngCookies', 'ngToast'])

.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}]);
