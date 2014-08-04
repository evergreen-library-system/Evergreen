'use strict';

describe('egHomeControllers', function(){
  beforeEach(module('egHome'));

  /* ---- LoginCtrl ---------------------------------- */

  var loginCtrl, loginScope;
  beforeEach(inject(function ($rootScope, $controller, $location) {
      // pass the workstation name via (mock) URL param
      $location.search({ws : 'TestWorkstation'});

      loginScope = $rootScope.$new();
      loginCtrl = $controller('LoginCtrl', {$scope: loginScope});
  }));

  it('should focus the login controller', inject(function() {
    expect(loginScope.focusMe).toBe(true);
  }));

});
