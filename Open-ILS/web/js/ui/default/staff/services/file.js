/**
 * File upload reader.
 * http://stackoverflow.com/questions/17063000/ng-model-for-input-type-file
 *
 * After reading, the contents will be available in the scope variable
 * referred to by container="..."
 */

angular.module('egCoreMod')
.directive("egFileReader", [function () {
    return {
        scope: {
            container: "="
        },
        link: function (scope, element, attributes) {
            // TODO: support DataURL, etc. via attrs
            element.bind("change", function (changeEvent) {
                var reader = new FileReader();
                reader.onload = function (loadEvent) {
                    scope.$apply(function () {
                        scope.container = loadEvent.target.result;
                    });
                }
                reader.readAsText(changeEvent.target.files[0]);
            });
        }
    }
}])

.directive('egJsonExporter', ['FileSaver', 'Blob', function(FileSaver, Blob) {
    return {
        scope: {
            container: '=',
            defaultFileName: '='
        },
        link: function (scope, element, attributes) {
            element.bind('click', function (clickEvent) {
                var data = new Blob([JSON.stringify(scope.container)], {type : 'application/json'});
                FileSaver.saveAs(data, scope.defaultFileName);
            });
        }
    }
}])
;
