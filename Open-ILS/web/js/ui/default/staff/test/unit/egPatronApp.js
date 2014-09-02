'use strict';

describe('egPatronAppTest', function(){
  beforeEach(module('egPatronApp'));

  // basic controller sanity checks
  
  var patronCtrl, patronScope;
  beforeEach(inject(function ($rootScope, $controller, $location) {
      patronScope = $rootScope.$new();
      patronCtrl = $controller('PatronCtrl', {$scope: patronScope});
  }));

  /** patronSvc tests **/
  describe('patronSvcTests', function() {

    it('patronSvc should start with empty lists', inject(function(patronSvc) {
        expect(patronSvc.patrons.length).toEqual(0);
    }));

    it('patronSvc reset should clear data', inject(function(patronSvc) {
        patronSvc.checkout_overrides.a = 1;
        expect(Object.keys(patronSvc.checkout_overrides).length).toBe(1);
        patronSvc.resetPatronLists();
        expect(Object.keys(patronSvc.checkout_overrides).length).toBe(0);
        expect(patronSvc.holds.length).toBe(0);
    }));

  });

});
