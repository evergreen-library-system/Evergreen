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
            generator: '=',
            defaultFileName: '='
        },
        link: function (scope, element, attributes) {
            var name = scope.defaultFileName || 'evergreen-json-export';
            element.bind('click', function (clickEvent) {
                if (scope.generator) {
                    scope.generator().then(function(value) {
                        var data = new Blob([JSON.stringify(value)], {type : 'application/json'});
                        FileSaver.saveAs(data, name);
                    });
                } else {
                    var data = new Blob([JSON.stringify(scope.container)], {type : 'application/json'});
                    FileSaver.saveAs(data, name);
                }
            });
        }
    }
}])

// The following directives use a attr instead of binding to get the default file name!
.directive('egStringExporter', ['FileSaver', 'Blob', function(FileSaver, Blob) {
    return {
        scope: {
            contentType: '=',
            string: '=',
            generator: '=',
            defaultFileName: '@'
        },
        link: function (scope, element, attributes) {
            var type = scope.contentType || 'text/plain';
            var name = scope.defaultFileName || 'evergreen-string-export';
            element.bind('click', function (clickEvent) {
                if (scope.generator) {
                    scope.generator().then(function(value) {
                        var data = new Blob([value], {type : type});
                        FileSaver.saveAs(data, name);
                    });
                } else {
                    var data = new Blob([scope.string], {type : type});
                    FileSaver.saveAs(data, name);
                }
            });
        }
    }
}])

.directive('egLineExporter', ['FileSaver', 'Blob', function(FileSaver, Blob) {
    return {
        scope: {
            contentType: '=',
            jsonArray: '=',
            defaultFileName: '@'
        },
        link: function (scope, element, attributes) {
            element.bind('click', function (clickEvent) {
                var type = scope.contentType || 'text/plain';
                var fname = scope.defaultFileName || 'evergreen-string-export';
                FileSaver.saveAs(
                    new Blob(
                        scope.jsonArray.map(function (line) {
                            return JSON.stringify(line) + '\n';
                        }),
                        {type : type}
                    ),
                    fname
                );
            });
        }
    }
}])

;
