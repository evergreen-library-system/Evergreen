angular.module('egItemMissingPieces',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.controller('MissingPiecesCtrl',
       ['$scope','$q','$window','$location','egCore','egConfirmDialog','egAlertDialog','egCirc','egItem',
function($scope, $q, $window, $location, egCore, egConfirmDialog, egAlertDialog, egCirc, itemSvc) {
    
    $scope.selectMe = true; // focus text input
    $scope.args = {};

    function get_copy(barcode) {

        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            egCore.auth.token(), egCore.auth.user().ws_ou(), 
            'asset', barcode)

        .then(function(resp) { // get_barcodes

            if (evt = egCore.evt.parse(resp)) {
                console.error(evt.toString());
                return $q.reject();
            }

            if (!resp || !resp[0]) {
                $scope.bcNotFound = barcode;
                $scope.selectMe = true;
                return $q.reject();
            }

            return egCore.pcrud.search('acp', {id : resp[0].id}, {
                flesh : 3, 
                flesh_fields : {
                    acp : ['call_number'],
                    acn : ['record'],
                    bre : ['simple_record']
                },
                select : { 
                    // avoid fleshing MARC on the bre
                    // note: don't add simple_record.. not sure why
                    bre : ['id']
                } 
            })
        })
    }

    function mark_missing_pieces(copy) {
        itemSvc.mark_missing_pieces(copy,$scope);
    }

    $scope.print_letter = function() {
        egCore.print.print({
            context : 'mail',
            content_type : 'text/plain',
            content : $scope.letter
        });
    }

    // find the item by barcode, then proceed w/ missing pieces
    $scope.submitBarcode = function(args) {

        $scope.bcNotFound = null;
        if (!args.barcode) return;

        $scope.selectMe = false;
        $scope.letter = null;

        get_copy(args.barcode).then(function(c){ return mark_missing_pieces(c,$scope) });
    }

}])

