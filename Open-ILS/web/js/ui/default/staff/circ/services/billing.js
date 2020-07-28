/**
 * Shared services for patron billing.
 * 
 */

angular.module('egCoreMod')

.factory('egBilling', 
       ['$uibModal','$q','egCore',
function($uibModal , $q , egCore) {

    var service = {};

    // fetch a fleshed money.billable_xact
    service.fetchXact = function(xact_id) {
        return egCore.pcrud.retrieve('mbt', xact_id, {
            flesh : 6,
            flesh_fields : {
                mbt : ['summary','circulation','grocery','reservation'],
                circ: ['target_copy', 'circ_lib'],
                acp : ['call_number','location','status','age_protect'],
                acn : ['record','owning_lib'],
                bre : ['simple_record'],
                mg : ['billing_location']
            },
            select : {bre : ['id']}}, // avoid MARC
            {authoritative : true}
        );
    }

    // apply a patron billing.  If no xact is provided, a grocery xact is
    // created.
    service.billPatron = function(args, xact) {
        // apply a billing to an existing transaction
        if (xact) return service.createBilling(xact.id, args);

        // create a new grocery xact, then apply a billing
        return service.createGroceryXact(args)
        .then(function(xact_id) { 
            return service.createBilling(xact_id, args);
        });
    }

    // create a new grocery xact
    service.createGroceryXact = function(args) {
        var groc = new egCore.idl.mg();
        groc.billing_location(egCore.auth.user().ws_ou());
        groc.note(args.note);
        groc.usr(args.patron_id);
        
        // create the xact
        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.money.grocery.create',
            egCore.auth.token(), groc

        // create the billing on the new xact
        ).then(function(xact_id) {
            if (evt = egCore.evt.parse(xact_id)) 
                return alert(evt);
            return xact_id;
        });
    }

    // fetch the org-focused billing types
    // Cache on egEnv
    service.fetchBillingTypes = function() {
        if (egCore.env.cbt) {
            return $q.when(egCore.env.cbt.list);
        }

        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.billing_type.ranged.retrieve.all',
            egCore.auth.token(),
            egCore.auth.user().ws_ou()
        ).then(function(list) {
            list = list.filter(function(item) {
                // first 100 are reserved for system-generated bills
                return item.id() > 100;
            });
            egCore.env.absorbList(list, 'cbt');
            return list;
        });
    }

    // create a patron billing
    service.createBilling = function(xact_id, args) {
        var bill = new egCore.idl.mb();
        bill.xact(xact_id);
        bill.amount(args.amount);
        bill.btype(args.billingType);
        bill.billing_type(egCore.env.cbt.map[args.billingType].name());
        bill.note(args.note);

        return egCore.net.request(
            'open-ils.circ', 
            'open-ils.circ.money.billing.create',
            egCore.auth.token(), bill

        // check the billing response
        ).then(function(bill_id) {
            if (evt = egCore.evt.parse(bill_id)) {
                alert(evt);
            } else {
                return bill_id;
            }
        });
    }


    // Show the billing dialog.  
    // Allows users to select amount, billing type, and note.
    // args:
    //   xact OR xact_id : if null, creates a grocery xact
    //   patron OR patron_id
    service.showBillDialog = function(args) {

        return $uibModal.open({
            templateUrl: './circ/share/t_bill_patron_dialog',
            backdrop: 'static',
            controller: 
                   ['$scope','$uibModalInstance','$timeout','billingTypes','xact','patron',
            function($scope , $uibModalInstance , $timeout , billingTypes , xact , patron) {
                console.debug('billing patron ' + patron.id());
                $scope.focus = true;
                if (xact && xact._isfieldmapper)
                    xact = egCore.idl.toHash(xact);
                $scope.xact = xact;
                $scope.patron = patron;
                $scope.billingTypes = billingTypes;
                $scope.location = egCore.org.get(egCore.auth.user().ws_ou()),
                $scope.billArgs = {
                    billingType : 101, // default to stock Misc. billing type
                    xact : xact,
                    patron_id : patron.id()
                }
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
                $scope.updateDefaultPrice = function() {
                    var type = billingTypes.filter(function(t) {
                        return t.id() == $scope.billArgs.billingType })[0];
                    if (type.default_price()) {
                        $scope.billArgs.amount = parseFloat(type.default_price());
                    } else {
                        $scope.billArgs.amount = null;
                    }
                }
            }],
            resolve : {
                // if we don't already have them, fetch the billing types
                billingTypes : function() {
                    return service.fetchBillingTypes();
                }, 

                xact : function() {
                    if (args.xact) return $q.when(args.xact);
                    if (args.xact_id) return service.fetchXact(args.xact_id);
                    return $q.when();
                },

                patron : function() {
                    if (args.patron) return $q.when(args.patron);
                    return  egCore.pcrud.retrieve('au', args.patron_id,
                        {flesh : 1, flesh_fields : {au : ['card']}});
                }

            }
        }).result.then(
            function(args) {
                // send the billing to the server using the arguments
                // provided in the billing dialog, then refresh
                return service.billPatron(args, args.xact);
            }
        );
    }

    return service;
}]);

