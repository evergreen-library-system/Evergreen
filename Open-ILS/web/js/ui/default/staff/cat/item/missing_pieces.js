angular.module('egItemMissingPieces',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.controller('MissingPiecesCtrl',
       ['$scope','$q','$window','$location','egCore','egConfirmDialog','egAlertDialog','egCirc',
function($scope , $q , $window , $location , egCore , egConfirmDialog , egAlertDialog , egCirc) {
    
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

        egConfirmDialog.open(
            egCore.strings.CONFIRM_MARK_MISSING_TITLE,
            egCore.strings.CONFIRM_MARK_MISSING_BODY, {
            barcode : copy.barcode(), 
            title : copy.call_number().record().simple_record().title()

        }).result.then(function() {

            // kick off mark missing
            return egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.mark_item_missing_pieces',
                egCore.auth.token(), copy.id()
            )

        }).then(function(resp) {
            var evt = egCore.evt.parse(resp); // should always produce event

            if (evt.textcode == 'ACTION_CIRCULATION_NOT_FOUND') {
                return egAlertDialog.open(
                    egCore.strings.CIRC_NOT_FOUND, {barcode : copy.barcode()});
            }

            var payload = evt.payload;

            // TODO: open copy editor inline?  new tab?

            // print the missing pieces slip
            var promise = $q.when();
            if (payload.slip) {
                // wait for completion, since it may spawn a confirm dialog
                promise = egCore.print.print({
                    context : 'default', 
                    content_type : 'text/html',
                    content : payload.slip.template_output().data()
                });
            }

            if (payload.letter) {
                $scope.letter = payload.letter.template_output().data();
            }

            // apply patron penalty
            if (payload.circ) {
                promise.then(function() {
                    egCirc.create_penalty(payload.circ.usr())
                });
            }  

        });
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

        get_copy(args.barcode).then(mark_missing_pieces);
    }

}])

