angular.module('egCurbsideMod', ['egCoreMod'])
.factory('egCurbsideCoreSvc',
       ['egCore','orderByFilter','$q','$filter','$uibModal','ngToast','egConfirmDialog',
function(egCore , orderByFilter , $q , $filter , $uibModal , ngToast , egConfirmDialog) {
    var service = { };

    service.get_to_be_staged = function(offset, count) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.fetch_to_be_staged',
            egCore.auth.token(),
            egCore.auth.user().ws_ou(),
            count, // yep, count first
            offset
        );
    };
    service.get_latest_to_be_staged = function() {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.fetch_to_be_staged.latest',
            egCore.auth.token()
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                return undefined;
            } else {
                return resp;
            }
        });
    }

    service.get_staged = function(offset, count) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.fetch_staged',
            egCore.auth.token(),
            egCore.auth.user().ws_ou(),
            count, // yep, count first
            offset
        );
    };
    service.get_latest_staged = function() {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.fetch_staged.latest',
            egCore.auth.token()
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                return undefined;
            } else {
                return resp;
            }
        });
    }

    service.get_arrived = function(offset, count) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.fetch_arrived',
            egCore.auth.token(),
            egCore.auth.user().ws_ou(),
            count, // yep, count first
            offset
        );
    };
    service.get_latest_arrived = function() {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.fetch_arrived.latest',
            egCore.auth.token()
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                return undefined;
            } else {
                return resp;
            }
        });
    }

    service.get_delivered = function(offset, count) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.fetch_delivered',
            egCore.auth.token(),
            egCore.auth.user().ws_ou(),
            count, // yep, count first
            offset
        );
    };
    service.get_latest_delivered = function() {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.fetch_delivered.latest',
            egCore.auth.token()
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                return undefined;
            } else {
                return resp;
            }
        });
    }

    service.mark_staged = function(slot_id) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.mark_staged',
            egCore.auth.token(),
            slot_id
        );
    }
    service.mark_unstaged = function(slot_id) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.mark_unstaged',
            egCore.auth.token(),
            slot_id
        );
    }
    service.mark_arrived = function(slot_id) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.mark_arrived',
            egCore.auth.token(),
            slot_id
        );
    }
    service.mark_delivered = function(slot_id) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.mark_delivered',
            egCore.auth.token(),
            slot_id
        );
    }

    service.claim_staging = function(slot_id) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.claim_staging',
            egCore.auth.token(),
            slot_id
        );
    }
    service.unclaim_staging = function(slot_id) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.unclaim_staging',
            egCore.auth.token(),
            slot_id
        );
    }

    service.patron_blocked = function(usr) {
        if (usr.barred() == 't' ||
            usr.active() == 'f') {
            return true;
        }
        var expire = Date.parse(usr.expire_date());
        if (expire < new Date()) {
            return true;
        }
        var blocked_by_penalty = false;
        angular.forEach(usr.standing_penalties(), function(penalty) {
            if (blocked_by_penalty) return;
            if (penalty.stop_date()) return;
            if (!penalty.standing_penalty().block_list()) return;
            if (penalty.standing_penalty().block_list().match(/CIRC/))
                blocked_by_penalty = true;
        });
        return blocked_by_penalty;
    }

    return service;
}])

.directive('egCurbsideHoldsList', function() {
    return {
        restrict : 'E',
        transclude: true,
        templateUrl : './circ/curbside/t_holds_list',
        scope : {
            slot : '=',
            holds : '=',
            bibData : '='
        },
        controller : [
                    '$scope','egCore',
            function($scope , egCore) {
            }
        ]
    }
});
