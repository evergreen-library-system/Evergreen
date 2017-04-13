angular.module('egSerialsAppDep')

.directive('egPredictionWizard', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            patternCode : '=',
            onSave      : '=',
            showShare   : '=',
            viewOnly    : '='
        },
        templateUrl: './serials/t_prediction_wizard',
        controller:
       ['$scope','$q','egSerialsCoreSvc','egCore','egGridDataProvider',
function($scope , $q , egSerialsCoreSvc , egCore , egGridDataProvider) {

    $scope.tab = { active : 0 };
    if (angular.isUndefined($scope.showShare)) {
        $scope.showShare = true;
    }
    if (angular.isUndefined($scope.viewOnly)) {
        $scope.viewOnly = false;
    }

    // for use by ng-value
    $scope.True = true;
    $scope.False = false;

    // class for MARC21 serial prediction pattern
    // TODO move elsewhere
    function PredictionPattern(patternCode) {
        var self = this;
        this.use_enum = false;
        this.use_alt_enum = false;
        this.use_chron = false;
        this.use_alt_chron = false;
        this.use_calendar_changes = false;
        this.calendar_change = [];
        this.compress_expand = '3';
        this.caption_evaluation = '0';        
        this.enum_levels = [];
        this.alt_enum_levels = [];
        this.chron_levels = [];
        this.alt_chron_levels = [{ caption : null, display_caption: false }];
        this.frequency_type = 'preset';
        this.use_regularity = false;
        this.regularity = [];

        var nr_sf_map = {
            '8' : 'link',
            'n' : 'note',
            'p' : 'pieces_per_issuance',
            'w' : 'frequency',
            't' : 'copy_caption'
        }
        var enum_level_map = {
            'a' : 0,
            'b' : 1,
            'c' : 2,
            'd' : 3,
            'e' : 4,
            'f' : 5
        }
        var alt_enum_level_map = {
            'g' : 0,
            'h' : 1
        }
        var chron_level_map = {
            'i' : 0,
            'j' : 1,
            'k' : 2,
            'l' : 3
        }
        var alt_chron_level_map = {
            'm' : 0
        }

        var curr_enum_level = -1;
        var curr_alt_enum_level = -1;
        var curr_chron_level = -1;
        var curr_alt_chron_level = -1;
        if (patternCode && patternCode.length > 2 && (patternCode.length % 2 == 0)) {
            // set indicator values
            this.compress_expand = patternCode[0];
            this.caption_evaluation = patternCode[1];
            for (var i = 2; i < patternCode.length; i += 2) {
                var sf = patternCode[i];
                var value = patternCode[i + 1]; 
                if (sf in nr_sf_map) {
                    this[nr_sf_map[sf]] = value;
                    continue;
                }
                if (sf in enum_level_map) {
                    this.use_enum = true;
                    curr_enum_level = enum_level_map[sf];
                    this.enum_levels[curr_enum_level] = {
                        caption : value,
                        restart : false
                    }
                    continue;
                }
                if (sf in alt_enum_level_map) {
                    this.use_enum = true;
                    this.use_alt_enum = true;
                    curr_enum_level = -1;
                    curr_alt_enum_level = alt_enum_level_map[sf];
                    this.alt_enum_levels[curr_alt_enum_level] = {
                        caption : value,
                        restart : false
                    }
                    continue;
                }
                if (sf in chron_level_map) {
                    this.use_chron = true;
                    curr_chron_level = chron_level_map[sf];
                    var chron = {};
                    if (value.match(/^\(.*\)$/)) {
                        chron.display_caption = false;
                        chron.caption = value.replace(/^\(/, '').replace(/\)$/, '');
                    } else {
                        chron.display_caption = true;
                        chron.caption = value;
                    }
                    this.chron_levels[curr_chron_level] = chron;
                    continue;
                }
                if (sf in alt_chron_level_map) {
                    this.use_alt_chron = true;
                    curr_chron_level = -1;
                    curr_alt_chron_level = alt_chron_level_map[sf];
                    var chron = {};
                    if (value.match(/^\(.*\)$/)) {
                        chron.display_caption = false;
                        chron.caption = value.replace(/^\(/, '').replace(/\)$/, '');
                    } else {
                        chron.display_caption = true;
                        chron.caption = value;
                    }
                    this.alt_chron_levels[curr_alt_chron_level] = chron;
                    continue;
                }

                if (sf == 'u') {
                    var units = {
                        type : 'number'
                    };
                    if (value == 'und' || value == 'var') {
                        units.type = value;
                    } else if (!isNaN(parseInt(value))) {
                        units.value = parseInt(value);
                    } else {
                        continue; // escape garbage
                    }
                    if (curr_enum_level > 0) {
                        this.enum_levels[curr_enum_level].units_per_next_higher = units;
                    } else if (curr_alt_enum_level > 0) {
                        this.alt_enum_levels[curr_alt_enum_level].units_per_next_higher = units;
                    }
                }
                if (sf == 'v' && value == 'r') {
                    if (curr_enum_level > 0) {
                        this.enum_levels[curr_enum_level].restart = true;
                    } else if (curr_alt_enum_level > 0) {
                        this.alt_enum_levels[curr_alt_enum_level].restart = true;
                    }
                }
                if (sf == 'z') {
                    if (curr_enum_level > -1) {
                        this.enum_levels[curr_enum_level].numbering_scheme = value;
                    } else if (curr_alt_enum_level > -1) {
                        this.alt_enum_levels[curr_alt_enum_level].numbering_scheme = value;
                    }
                }
                if (sf == 'x') {
                    this.use_calendar_change = true;
                    value.split(',').forEach(function(chg) {
                        var calendar_change = {
                            type   : null,
                            season : null,
                            month  : null,
                            day    : null
                        }
                        if (chg.length == 2) {
                            if (chg >= '21') {
                                calendar_change.type = 'season';
                                calendar_change.season = chg;
                            } else {
                                calendar_change.type = 'month';
                                calendar_change.month = chg;
                            }
                        } else if (chg.length == 4) {
                            calendar_change.type = 'date';
                            calendar_change.month = chg.substring(0, 2);
                            calendar_change.day   = chg.substring(2, 4);
                        }
                        self.calendar_change.push(calendar_change);
                    });
                }
                if (sf == 'y') {
                    this.use_regularity = true;
                    var regularity_type = value.substring(0, 1);
                    var parts = [];
                    var chron_type = value.substring(1, 2);
                    value.substring(2).split(/,/).forEach(function(value) {
                        var piece = {};
                        if (regularity_type == 'c') {
                            piece.combined_code = value;
                        } else if (chron_type == 'd') {
                            if (value.match(/^\d\d$/)) {
                                piece.sub_type = 'day_of_month';
                                piece.day_of_month = value;
                            } else if (value.match(/^\d\d\d\d$/)) {
                                piece.sub_type = 'specific_date';
                                piece.specific_date = value;
                            } else {
                                piece.sub_type = 'day_of_week';
                                piece.day_of_week = value;
                            }
                        } else if (chron_type == 'm') {
                            piece.sub_type = 'month';
                            piece.month = value;
                        } else if (chron_type == 's') {
                            piece.sub_type = 'season';
                            piece.season = value;
                        } else if (chron_type == 'w') {
                            if (value.match(/^\d\d\d\d$/)) {
                                piece.sub_type = 'week_in_month';
                                piece.week   = value.substring(0, 2);
                                piece.month  = value.substring(2, 4);
                            } else if (value.match(/^\d\d[a-z][a-z]$/)) {
                                piece.sub_type = 'week_day';
                                piece.week = value.substring(0, 2);
                                piece.day  = value.substring(2, 4);
                            } else if (value.length == 6) {
                                piece.sub_type = 'week_day_in_month';
                                piece.month = value.substring(0, 2);
                                piece.week  = value.substring(2, 4);
                                piece.day   = value.substring(4, 6);
                            }
                        } else if (chron_type == 'y') {
                            piece.sub_type = 'year';
                            piece.year = value;
                        }
                        parts.push(piece);
                    });
                    self.regularity.push({
                        regularity_type  : regularity_type,
                        chron_type       : chron_type,
                        parts            : parts
                    });
                }
            }
        }

        if (self.frequency) {
            if (self.frequency.match(/^\d+$/)) {
                self.frequency_type = 'numeric';
                self.frequency_numeric = self.frequency;
            } else {
                self.frequency_type = 'preset';
                self.frequency_preset = self.frequency;
            }
        }

        // return current pattern compiled to subfield list
        this.compile = function() {
            var patternCode = [];
            patternCode.push(self.compress_expand);
            patternCode.push(self.caption_evaluation);
            patternCode.push('8');
            patternCode.push(self.link);
            if (self.use_enum) {
                for (var i = 0; i < self.enum_levels.length; i++) {
                    patternCode.push(['a', 'b', 'c', 'd', 'e', 'f'][i]);
                    patternCode.push(self.enum_levels[i].caption);
                    if (i > 0 && self.enum_levels[i].units_per_next_higher) {
                        patternCode.push('u');
                        if (self.enum_levels[i].units_per_next_higher.type == 'number') {
                            patternCode.push(self.enum_levels[i].units_per_next_higher.value.toString());
                        } else {
                            patternCode.push(self.enum_levels[i].units_per_next_higher.type);
                        }
                    }
                    if (i > 0 && self.enum_levels[i].restart != null) {
                        patternCode.push('v');
                        patternCode.push(self.enum_levels[i].restart ? 'r' : 'c');
                    }
                }
            }
            if (self.use_enum && self.use_alt_enum) {
                for (var i = 0; i < self.alt_enum_levels.length; i++) {
                    patternCode.push(['g','h'][i]);
                    patternCode.push(self.alt_enum_levels[i].caption);
                    if (i > 0 && self.alt_enum_levels[i].units_per_next_higher) {
                        patternCode.push('u');
                        if (self.alt_enum_levels[i].units_per_next_higher.type == 'number') {
                            patternCode.push(self.alt_enum_levels[i].units_per_next_higher.value);
                        } else {
                            patternCode.push(self.alt_enum_levels[i].units_per_next_higher.type);
                        }
                    }
                    if (i > 0 && self.alt_enum_levels[i].restart != null) {
                        patternCode.push('v');
                        patternCode.push(self.alt_enum_levels[i].restart ? 'r' : 'c');
                    }
                }
            }
            var chron_sfs = (self.use_enum) ? ['i', 'j', 'k', 'l'] : ['a', 'b', 'c', 'd'];
            if (self.use_chron) {
                for (var i = 0; i < self.chron_levels.length; i++) {
                    patternCode.push(chron_sfs[i],
                        self.chron_levels[i].display_caption ?
                           self.chron_levels[i].caption :
                           '(' + self.chron_levels[i].caption + ')'
                    );
                }
            }
            var alt_chron_sf = (self.use_enum) ? 'm' : 'g';
            if (self.use_alt_chron) {
                patternCode.push(alt_chron_sf,
                    self.alt_chron_levels[0].display_caption ?
                       self.alt_chron_levels[0].caption :
                       '(' + self.alt_chron_levels[0].caption + ')'
                );
            }
            // frequency
            patternCode.push('w',
                self.frequency_type == 'numeric' ?
                    self.frequency_numeric :
                    self.frequency_preset
            );
            // calendar change
            if (self.use_enum && self.use_calendar_change) {
                patternCode.push('x');
                patternCode.push(self.calendar_change.map(function(chg) {
                    if (chg.type == 'season') {
                        return chg.season;
                    } else if (chg.type == 'month') {
                        return chg.month;
                    } else if (chg.type == 'date') {
                        return chg.month + chg.day;
                    }
                }).join(','));
            }
            // regularity
            if (self.use_regularity) {
                self.regularity.forEach(function(reg) {
                    patternCode.push('y');
                    var val = reg.regularity_type + reg.chron_type;
                    val += reg.parts.map(function(part) {
                        if (reg.regularity_type == 'c') {
                            return part.combined_code;
                        } else if (reg.chron_type == 'd') {
                            return part[part.sub_type];
                        } else if (reg.chron_type == 'm') {
                            return part.month;
                        } else if (reg.chron_type == 'w') {
                            if (part.sub_type == 'week_in_month') {
                                return part.week + part.month;
                            } else if (part.sub_type == 'week_day') {
                                return part.week + part.day;
                            } else if (part.sub_type == 'week_day_in_month') {
                                return part.month + part.week + part.day;
                            }
                        } else if (reg.chron_type == 's') {
                            return part.season;
                        } else if (reg.chron_type == 'y') {
                            return part.year;
                        }
                    }).join(',');
                    patternCode.push(val);
                });
            }
            return patternCode;
        }

        this.compile_stringify = function() {
            return JSON.stringify(this.compile(), null, 2);
        }

        this.add_enum_level = function() {
            if (self.enum_levels.length < 6) {
                self.enum_levels.push({
                    caption : null,
                    units_per_next_higher : { type : 'und' },
                    restart : false
                });
            }
        }
        this.drop_enum_level = function() {
            if (self.enum_levels.length > 1) {
                self.enum_levels.pop();
            }
        }

        this.add_alt_enum_level = function() {
            if (self.alt_enum_levels.length < 2) {
                self.alt_enum_levels.push({
                    caption : null,
                    units_per_next_higher : { type : 'und' },
                    restart : false
                });
            }
        }
        this.drop_alt_enum_level = function() {
            if (self.alt_enum_levels.length > 1) {
                self.alt_enum_levels.pop();
            }
        }
        this.remove_calendar_change = function(idx) {
            if (self.calendar_change.length > idx) {
                self.calendar_change.splice(idx, 1);
            }
        }
        this.add_calendar_change = function() {
            self.calendar_change.push({
                type   : null,
                season : null,
                month  : null,
                day    : null
            });
        }

        this.add_chron_level = function() {
            if (self.chron_levels.length < 4) {
                self.chron_levels.push({
                    caption : null,
                    display_caption : false
                });
            }
        }
        this.drop_chron_level = function() {
            if (self.chron_levels.length > 1) {
                self.chron_levels.pop();
            }
        }
        this.add_regularity = function() {
            self.regularity.push({
                regularity_type : null,
                chron_type : null,
                parts : [{ sub_type : null }]
            });
        }
        this.remove_regularity = function(idx) {
            if (self.regularity.length > idx) {
                self.regularity.splice(idx, 1);
            }
            // and add a blank entry back if need be
            if (self.regularity.length == 0) {
                self.add_regularity();
            }
        }
        this.add_regularity_part = function(reg) {
            reg.parts.push({
                sub_type : null
            });
        }
        this.remove_regularity_part = function(reg, idx) {
            if (reg.parts.length > idx) {
                reg.parts.splice(idx, 1);
            }
            // and add a blank entry back if need be
            if (reg.parts.length == 0) {
                self.add_regularity_part(reg);
            }
        }

        this.display_enum_captions = function() {
            return self.enum_levels.map(function(lvl) {
                return lvl.caption;
            }).join(', ');
        }
        this.display_alt_enum_captions = function() {
            return self.alt_enum_levels.map(function(lvl) {
                return lvl.caption;
            }).join(', ');
        }
        this.display_chron_captions = function() {
            return self.chron_levels.map(function(lvl) {
                return lvl.caption;
            }).join(', ');
        }
        this.display_alt_chron_captions = function() {
            return self.alt_chron_levels.map(function(lvl) {
                return lvl.caption;
            }).join(', ');
        }

        if (!patternCode) {
            // starting from scratch, ensure there's
            // enough so that the input wizard can be used
            this.use_enum = true;
            this.use_chron = true;
            this.link = 0;
            self.add_enum_level();
            self.add_alt_enum_level();
            self.add_chron_level();
            self.add_calendar_change();
            self.add_regularity();
        } else {
            // fill in potential missing bits
            if (!self.use_enum && self.enum_levels.length == 0) self.add_enum_level();
            if (!self.use_alt_enum && self.alt_enum_levels.length == 0) self.add_alt_enum_level();
            if (!self.use_chron && self.chron_levels.length == 0) self.add_chron_level();
            if (!self.use_calendar_change) self.add_calendar_change();
            if (!self.use_regularity) self.add_regularity();
        }
    }
    // TODO chron only

    if ($scope.patternCode) {
        $scope.pattern = new PredictionPattern(JSON.parse($scope.patternCode));
    } else {
        $scope.pattern = new PredictionPattern();
    }

    // possible sharing
    $scope.share = {
        pattern_name : null,
        depth        : 0
    };

    $scope.chron_captions = [];
    $scope.alt_chron_captions = [];

    $scope.handle_save = function() {
        $scope.patternCode = JSON.stringify($scope.pattern.compile());
        if ($scope.share.pattern_name !== null) {
            var spt = new egCore.idl.spt();
            spt.name($scope.share.pattern_name);
            spt.pattern_code($scope.patternCode);
            spt.share_depth($scope.share.depth);
            spt.owning_lib(egCore.auth.user().ws_ou());
            egCore.pcrud.create(spt).then(function() {
                if (angular.isFunction($scope.onSave)) {
                    $scope.onSave($scope.patternCode);
                }
            });
        } else {
            if (angular.isFunction($scope.onSave)) {
                $scope.onSave($scope.patternCode);
            }
        }
    }

}]
    }
})

.directive('egChronSelector', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            ngModel        : '=',
            chronLevel     : '=',
            linkedSelector : '=',
        },
        templateUrl: './serials/t_chron_selector',
        controller:
       ['$scope','$q','egCore',
function($scope , $q , egCore) {
        $scope.options = [
            { value : 'year',   label : egCore.strings.CHRON_LABEL_YEAR,   disabled: false },
            { value : 'season', label : egCore.strings.CHRON_LABEL_SEASON, disabled: false },
            { value : 'month',  label : egCore.strings.CHRON_LABEL_MONTH,  disabled: false },
            { value : 'week',   label : egCore.strings.CHRON_LABEL_WEEK,   disabled: false },
            { value : 'day',    label : egCore.strings.CHRON_LABEL_DAY,    disabled: false },
            { value : 'hour',   label : egCore.strings.CHRON_LABEL_HOUR,   disabled: false }
        ];
        var levels = {
            'year'   : 0,
            'season' : 1,
            'month'  : 1,
            'week'   : 2,
            'day'    : 3,
            'hour'   : 4
        };
        $scope.$watch('ngModel', function(newVal, oldVal) {
            $scope.linkedSelector[$scope.chronLevel] = $scope.ngModel;
        });
        $scope.$watch('linkedSelector', function(newVal, oldVal) {
            if ($scope.chronLevel > 0 && $scope.linkedSelector[$scope.chronLevel - 1]) {
                var level_to_disable = levels[ $scope.linkedSelector[$scope.chronLevel - 1] ];
                for (var i = 0; i < $scope.options.length; i++) {
                    $scope.options[i].disabled =
                        (levels[ $scope.options[i].value ] <= level_to_disable);
                }
            }
        }, true);
}]
    }
})

.directive('egMonthSelector', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            ngModel : '='
        },
        templateUrl: './serials/t_month_selector',
        controller:
       ['$scope','$q',
function($scope , $q) {
}]
    }
})

.directive('egSeasonSelector', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            ngModel : '='
        },
        templateUrl: './serials/t_season_selector',
        controller:
       ['$scope','$q',
function($scope , $q) {
}]
    }
})

.directive('egWeekInMonthSelector', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            ngModel : '='
        },
        templateUrl: './serials/t_week_in_month_selector',
        controller:
       ['$scope','$q',
function($scope , $q) {
}]
    }
})

.directive('egDayOfWeekSelector', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            ngModel : '='
        },
        templateUrl: './serials/t_day_of_week_selector',
        controller:
       ['$scope','$q',
function($scope , $q) {
}]
    }
})

.directive('egMonthDaySelector', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            month : '=',
            day   : '='
        },
        templateUrl: './serials/t_month_day_selector',
        controller:
       ['$scope','$q',
function($scope , $q) {
    if ($scope.month == null) $scope.month = '01';
    if ($scope.day   == null) $scope.day   = '01';
    $scope.dt = new Date(2012, parseInt($scope.month) - 1, parseInt($scope.day), 1);
    $scope.options = {
        minMode : 'day',
        maxMode : 'day',
        datepickerMode : 'day',
        showWeeks : false,
        // use a leap year, though any publisher who uses 29 February as a
        // calendar change is simply trolling
        // also note that when https://github.com/angular-ui/bootstrap/issues/1993
        // is fixed, setting minDate and maxDate would make sense, as
        // user wouldn't be able to keeping hit the left or right arrows
        // past the end of the range
        // minDate : new Date('2012-01-01 00:00:01'),
        // maxDate : new Date('2012-12-31 23:59:59'),
        formatDayTitle : 'MMMM',
    }
    $scope.datePickerIsOpen = false;
    $scope.$watch('dt', function(newVal, oldVal) {
        if (newVal != oldVal) {
            $scope.day   = ('00' + $scope.dt.getDate() ).slice(-2);
            $scope.month = ('00' + ($scope.dt.getMonth() + 1)).slice(-2);
        }
    });
}]
    }
})

.directive('egPredictionPatternSummary', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            pattern : '<'
        },
        templateUrl: './serials/t_pattern_summary',
        controller:
       ['$scope','$q',
function($scope , $q) {
}]
    }
})

