// Refer to the online docs for more details: https://nightwatchjs.org/gettingstarted/configuration/
const Services = {}; loadServices();

//  _   _  _         _      _                     _          _
// | \ | |(_)       | |    | |                   | |        | |
// |  \| | _   __ _ | |__  | |_ __      __  __ _ | |_   ___ | |__
// | . ` || | / _` || '_ \ | __|\ \ /\ / / / _` || __| / __|| '_ \
// | |\  || || (_| || | | || |_  \ V  V / | (_| || |_ | (__ | | | |
// \_| \_/|_| \__, ||_| |_| \__|  \_/\_/   \__,_| \__| \___||_| |_|
//             __/ |
//            |___/

module.exports = {
  // An array of folders (excluding subfolders) where your tests are located;
  // if this is not specified, the test source must be passed as the second argument to the test runner.
  src_folders: ['nightwatch/src'],

  filter: ['**/*.spec.ts'],

  // See https://nightwatchjs.org/guide/working-with-page-objects/
  page_objects_path: ['nightwatch/pages/**'],

  // See https://nightwatchjs.org/guide/extending-nightwatch/#writing-custom-commands
  custom_commands_path: '',

  // See https://nightwatchjs.org/guide/extending-nightwatch/#writing-custom-assertions
  custom_assertions_path: '',

  // See https://nightwatchjs.org/guide/#external-globals
  globals_path : '',

  webdriver: {},

  test_settings: {
    default: {
      disable_error_log: false,
      launch_url: 'https://localhost',

      screenshots: {
        enabled: false,
        path: 'screens',
        on_failure: true
      },

      desiredCapabilities: {
        browserName : 'firefox',
        acceptInsecureCerts: true
      },

      webdriver: {
        start_process: true,
        server_path: ''
      },

      globals: {
        axeSettings: {
          options: {
            rules: {
              'aria-required-children': {enabled: false}
            }
          }
        }

      }
    },

    firefox: {
      desiredCapabilities : {
        browserName : 'firefox',
        alwaysMatch: {
          acceptInsecureCerts: true,
          'moz:firefoxOptions': {
            args: [
              //'-headless',
              // '-verbose'
            ]
          }
        }
      },
      webdriver: {
        start_process: true,
        server_path: '',
        cli_args: [
          // very verbose geckodriver logs
          // '-vv'
        ]
      }
    },
    // To test with chrome:
    // $ npm install --save-dev chromedriver
    // $ npx ng e2e --env chrome
    chrome: {
      desiredCapabilities : {
        browserName : 'chrome',
        alwaysMatch: {
          acceptInsecureCerts: true,
        }
      },
      webdriver: {
        start_process: true,
        server_path: '',
        cli_args: [
        ]
      }
    },
    // $ npx ng e2e --env chrome-headless
    'chrome-headless': {
      desiredCapabilities : {
        browserName : 'chrome',
        alwaysMatch: {
          acceptInsecureCerts: true,
        },
        chromeOptions : {
            args: ['headless', 'no-sandbox', 'disable-gpu']
        },
        chromeOptions : {
            args: ['headless', 'no-sandbox', 'disable-gpu']
        }
      },
      webdriver: {
        start_process: true,
        server_path: '',
        cli_args: [
        ]
      }
    }
  }
};

function loadServices() {
  try {
    Services.seleniumServer = require('selenium-server');
  } catch (err) {}

  try {
    Services.chromedriver = require('chromedriver');
  } catch (err) {}

  try {
    Services.geckodriver = require('geckodriver');
  } catch (err) {}
}
