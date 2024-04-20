// Karma configuration file, see link for more information
// https://karma-runner.github.io/1.0/config/configuration-file.html

module.exports = function (config) {
  config.set({
    basePath: '',
    frameworks: ['jasmine', '@angular-devkit/build-angular'],
    plugins: [
      require('karma-jasmine'),
      require('karma-chrome-launcher'),
      require('karma-firefox-launcher'),
      require('karma-jasmine-html-reporter'),
      require('karma-coverage'),
      require('karma-coverage-istanbul-reporter'),
      require('@angular-devkit/build-angular/plugins/karma')
    ],
    client:{
      clearContext: false // leave Jasmine Spec Runner output visible in browser
    },
    coverageIstanbulReporter: {
      dir: require('path').join(__dirname, 'coverage'), reports: [ 'html', 'lcovonly' ],
      fixWebpackSourcePaths: true
    },
    angularCli: {
      environment: 'dev'
    },
    reporters: ['progress', 'kjhtml'],
    port: 9876,
    colors: true,
    logLevel: config.LOG_INFO,
    autoWatch: true,
    browsers: ['ChromeHeadless','FirefoxHeadless'],
    customLaunchers: {
        'FirefoxHeadless': {
            base: 'Firefox',
            flags: [
                '-headless',
            ],
        }
    },
    singleRun: true,
    files: [
      '/openils/lib/javascript/md5.js',
      '/openils/lib/javascript/JSON_v1.js',
      '/openils/lib/javascript/opensrf.js',
      '/openils/lib/javascript/opensrf_ws.js',
      // mock data for testing only
      'src/test_data/IDL2js.js',
      'src/test_data/eg_mock.js',
    ]
  });
};
