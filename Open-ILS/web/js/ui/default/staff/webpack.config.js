const path = require('path');
const merge = require('webpack-merge');
const webpack = require('webpack');
const CleanWebpackPlugin = require('clean-webpack-plugin');
const UglifyJSPlugin = require('uglifyjs-webpack-plugin');
const CopyWebpackPlugin = require('copy-webpack-plugin');

const buildPath = 'build';

const CSS_FILES = [
  'node_modules/angular-hotkeys/build/hotkeys.min.css',
  'node_modules/bootstrap/dist/css/bootstrap.min.css',
  'node_modules/ng-toast/dist/ngToast.min.css',
  'node_modules/ng-toast/dist/ngToast-animations.min.css',
  'node_modules/angular-tree-control/css/tree-control.css',
  'node_modules/angular-tree-control/css/tree-control-attribute.css',
  'node_modules/angular-tablesort/tablesort.css'
];

const FONT_FILES = [
  'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.eot',
  'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.svg',
  'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.ttf',
  'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.woff',
  'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.woff2'
];

const IMAGE_FILES = [
  'node_modules/angular-tree-control/images/sample.png',
  'node_modules/angular-tree-control/images/node-opened-2.png',
  'node_modules/angular-tree-control/images/folder.png',
  'node_modules/angular-tree-control/images/node-closed.png',
  'node_modules/angular-tree-control/images/node-closed-light.png',
  'node_modules/angular-tree-control/images/node-opened.png',
  'node_modules/angular-tree-control/images/node-opened-light.png',
  'node_modules/angular-tree-control/images/folder-closed.png',
  'node_modules/angular-tree-control/images/node-closed-2.png',
  'node_modules/angular-tree-control/images/file.png'
]

// Some common JS files are left un-bundled.
// https://github.com/webpack/webpack/issues/3128
const JS_FILES = [
  './node_modules/moment/min/moment-with-locales.min.js',
  './node_modules/moment-timezone/builds/moment-timezone-with-data.min.js',
  './node_modules/iframe-resizer/js/iframeResizer.contentWindow.min.js',
  './node_modules/iframe-resizer/js/iframeResizer.min.js',
  // lovefield is loaded from multiple locations.  Make it stand-alone
  // so we only need a single copy.
  './node_modules/lovefield/dist/lovefield.min.js'
]


// Copy files as-is from => to.
const directCopyFiles = [

  // jquery is copied to the common build location, up one directory.
  {from: './node_modules/jquery/dist/jquery.min.js', 
     to: __dirname + '/../common/build/js'},

  // and likewise for glide
  {from: './node_modules/@glidejs/glide/dist',
     to: __dirname + '/../common/build/js/glide'}
];

CSS_FILES.forEach(file => directCopyFiles.push({from: file, to: './css'}));
FONT_FILES.forEach(file => directCopyFiles.push({from: file, to: './fonts'}));
IMAGE_FILES.forEach(file => directCopyFiles.push({from: file, to: './images'}));
JS_FILES.forEach(file => directCopyFiles.push({from: file, to: './js'}));

// EG JS files loaded on every page
const coreJsFiles = [
  './services/core.js',
  './services/strings.js',
  './services/idl.js',
  './services/event.js',
  './services/net.js',
  './services/auth.js',
  './services/pcrud.js',
  './services/env.js',
  './services/org.js',
  './services/startup.js',
  './services/hatch.js',
  './services/print.js',
  './services/audio.js',
  './services/coresvc.js',
  './services/user.js',
  './services/navbar.js',
  './services/ui.js',
  './services/i18n.js',
  './services/date.js',
  './services/op_change.js',
  './services/lovefield.js'
];

// 3rd-party (AKA vendor) JS files loaded on every page.
// Webpack knows to look in ./node_modules/
const vendorJsFiles = [
  'angular',
  'angular-route',
  'angular-ui-bootstrap',
  'angular-hotkeys',
  'angular-file-saver',
  'angular-location-update',
  'angular-animate',
  'angular-sanitize',
  'angular-cookies',
  'ng-toast',
  'angular-tree-control',
  'angular-tree-control/context-menu.js',
  'angular-order-object-by',
  'angular-tablesort'
];


let commmonOptions = {
  // As of today, we are only bundling common files.  Individual app.js
  // and optional service files are still imported via script tags.
  entry: {
    core: coreJsFiles,
    vendor: vendorJsFiles
  },
  plugins: [
    new CleanWebpackPlugin([buildPath]),
    new CopyWebpackPlugin(directCopyFiles, {copyUnmodified: true}),
    new webpack.optimize.CommonsChunkPlugin({
      names: ['core', 'vendor'], // ORDER MATTERS
      minChunks: 2 // TODO: huh?
    })
  ],
  output: {
    filename: 'js/[name].bundle.js',
    path: path.resolve(__dirname, buildPath)
  }
};

// improve debugging during development with inline source maps
// for bundled files.
let devOptions = {
  devtool: 'inline-source-map',
  plugins: [
    // Avoid minifiying the core bundle in development mode.
    // TODO: Add other bundles as necessary, but leave the 'vendor'
    // bundle out, since we always want to minify that (it's big).
    new UglifyJSPlugin({
      exclude: [/core/]
    })
  ],
  watchOptions: {
    aggregateTimeout: 300,
    poll: 1000,
    ignored : [
        /node_modules/
    ]
  }
};

// minify for production
let prodOptions = {
  plugins: [
    new UglifyJSPlugin()
  ],
};

module.exports = env => env.prod ? 
    merge(commmonOptions, prodOptions) : merge(commmonOptions, devOptions); 

