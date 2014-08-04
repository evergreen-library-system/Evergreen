/**
 * egStatusBar
 *
 * Displays key information and messages to the user.
 *
 * Currently displays network connection status, egHatch connection
 * status, and messages delivered via 
 * $scope.$emit('egStatusBarMessage', msg)
 */

angular.module('egCoreMod')

.directive('egStatusBar', function() {
    return {
        restrict : 'AE',
        replace : true,
        templateUrl : 'eg-status-bar-template',
        controller : [
                    '$scope','$rootScope','egHatch',
            function($scope , $rootScope , egHatch) {
            $scope.messages = []; // keep a log of recent messages

            $scope.netConnected = function() {
                // TODO: should should be abstracted through egNet
                return OpenSRF.websocketConnected();
            }

            // update the UI whenever we lose connection
            OpenSRF.onWebSocketClosed = function() {
                $scope.$apply();
            }

            $scope.hatchConnected = function() {
                return egHatch.hatchAvailable;
            }

            // update the UI whenever we lose connection
            egHatch.onHatchClose = function() {
                $scope.$apply();
            }

            // update the UI whenever we lose connection
            egHatch.onHatchOpen = function() {
                $scope.$apply();
            }

            $scope.hatchConnect = function() {
                egHatch.hatchConnect();
            }

            $rootScope.$on('egStatusBarMessage', function(evt, args) {
                $scope.messages.unshift(args.message);

                // ensure the list does not exceed 10 messages
                // TODO: configurable?
                $scope.messages.splice(10, 1); 
            });
        }]
    }
});
