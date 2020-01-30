module.exports = function(config){
    config.set({
    basePath : '../',

    // config.LOG_DISABLE || config.LOG_ERROR || config.LOG_WARN || config.LOG_INFO || config.LOG_DEBUG
    logLevel: config.LOG_INFO,

    files : [
      'build/js/lovefield.min.js',
      'build/js/vendor.bundle.js',
      'build/js/core.bundle.js',
      'node_modules/angular-mocks/angular-mocks.js', // testing only
      'node_modules/angular-file-saver/dist/angular-file-saver.bundle.min.js',
      'node_modules/ng-toast/dist/ngToast.min.js',
      'node_modules/angular-sanitize/angular-sanitize.min.js',
      /* OpenSRF must be installed first */
      '/openils/lib/javascript/md5.js',
      '/openils/lib/javascript/JSON_v1.js',
      '/openils/lib/javascript/opensrf.js',
      '/openils/lib/javascript/opensrf_ws.js',

      // mock data for testing only
      'test/data/IDL2js.js',
      'test/data/eg_mock.js',

      // service/*.js have to be loaded in order
      'services/grid.js',
      'services/patron_search.js',
      'services/user-bucket.js',
      'services/batch_promises.js',

      // load app scripts
      'app.js',
      'circ/**/*.js',
      'cat/**/*.js',
      'reporter/**/*.js',
      'admin/**/*.js',
      'test/unit/egIDL.js', // order matters for some of these
      'test/unit/egOrg.js', 
      'test/unit/**/*.js'
    ],

    proxies: {
        '/js/ui/default/staff/offline-db-worker.js' : 'offline-db-worker.js'
    },

    // test results reporter to use
    // possible values: 'dots', 'progress', 'junit', 'growl', 'coverage'
    reporters: ['spec'],  // detailed report
    //reporters: ['progress'], // summary report

    // enable / disable colors in the output (reporters and logs)
    colors: true,

    // enable / disable watching file and executing tests whenever any file changes
    autoWatch : false,

    frameworks: ['jasmine'],

    browsers: ['ChromeHeadless','FirefoxHeadless'],

    customLaunchers: {
        'FirefoxHeadless': {
            base: 'Firefox',
            flags: [
                '-headless',
            ],
            prefs: {
                'privacy.resistFingerprinting': false,
                'general.useragent.override': 'FirefoxHeadless'
            },
        }
    },

    // web server port
    port: 9876,

    /*
    coverageReporter: {
      type : 'html',
      dir : 'coverage/',
    },

    preprocessors: {
      '../src/*.js': ['coverage']
    },
    */

    // If browser does not capture in given timeout [ms], kill it
    captureTimeout: 60000,

    // Continuous Integration mode
    // if true, it capture browsers, run tests and exit
    singleRun: true
})}
