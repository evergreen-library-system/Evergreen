module.exports = function(grunt) {

  // Project configuration.
  var config = { 
    pkg: grunt.file.readJSON('package.json'),

    // copy the files we care about from fetched dependencies
    // into our build directory
    copy: {

      js : {
        files: [{ 
          dest: 'build/js/', 
          flatten: true,
          filter: 'isFile',
          expand : true,
          src: [
            'node_modules/angular/angular.min.js',
            'node_modules/angular/angular.min.js.map',
            'node_modules/angular-animate/angular-animate.min.js',
            'node_modules/angular-animate/angular-animate.min.js.map',
            'node_modules/angular-sanitize/angular-sanitize.min.js',
            'node_modules/angular-sanitize/angular-sanitize.min.js.map',
            'node_modules/angular-route/angular-route.min.js',
            'node_modules/angular-route/angular-route.min.js.map',
            'node_modules/angular-ui-bootstrap/dist/ui-bootstrap.js',
            'node_modules/angular-ui-bootstrap/dist/ui-bootstrap-tpls.js',
            'node_modules/angular-hotkeys/build/hotkeys.min.js',
            'node_modules/angular-file-saver/dist/angular-file-saver.bundle.min.js',
            'node_modules/angular-location-update/angular-location-update.min.js',
            'node_modules/angular-tree-control/angular-tree-control.js',
            'node_modules/ng-toast/dist/ngToast.min.js',
            'node_modules/angular-cookies/angular-cookies.min.js',
            'node_modules/angular-cookies/angular-cookies.min.js.map',
            'node_modules/iframe-resizer/js/iframeResizer.min.js',
            'node_modules/iframe-resizer/js/iframeResizer.map',
            'node_modules/iframe-resizer/js/iframeResizer.contentWindow.min.js',
            'node_modules/angular-order-object-by/src/ng-order-object-by.js',
            'node_modules/angular-tablesort/js/angular-tablesort.js',
            'node_modules/lovefield/dist/lovefield.min.js',
            'node_modules/lovefield/dist/lovefield.min.js.map',
            'node_modules/moment/min/moment-with-locales.min.js',
            'node_modules/moment-timezone/builds/moment-timezone-with-data.min.js'
          ]
        },
        {
          dest: '../common/build/js/', 
          flatten: true,
          filter: 'isFile',
          expand : true,
          src: [
            'node_modules/jquery/dist/jquery.min.js'
          ]
        }]
      },

      css : {
        files : [{
          dest : 'build/css/',
          flatten : true,
          filter : 'isFile',
          expand : true,
          src : [
            'node_modules/angular-hotkeys/build/hotkeys.min.css',
            'node_modules/bootstrap/dist/css/bootstrap.min.css', 
            'node_modules/ng-toast/dist/ngToast.min.css',
            'node_modules/ng-toast/dist/ngToast-animations.min.css',
            'node_modules/angular-tree-control/css/tree-control.css',
            'node_modules/angular-tree-control/css/tree-control-attribute.css',
            'node_modules/angular-tablesort/tablesort.css'
          ]
        }]
      },

      fonts : {
        files : [{
          dest : 'build/fonts/',
          flatten : true,
          filter : 'isFile',
          expand : true,
          src : [
            'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.eot',
            'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.svg',
            'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.ttf',
            'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.woff',
            'node_modules/bootstrap/dist/fonts/glyphicons-halflings-regular.woff2'
          ]
        }]
      },

      images : {
        files : [{
          dest : 'build/images/',
          flatten : true,
          filter : 'isFile',
          expand : true,
          src : [
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
        }]
      }
    },

    // combine our CSS deps
    // note: minification also supported, but not required (yet).
    cssmin: {
      combine: {
        files: {
          'build/css/evergreen-staff-client-deps.<%= pkg.version %>.min.css' : [
            'build/css/hotkeys.min.css',
            'build/css/bootstrap.min.css',
            'build/css/ngToast.min.css',
            'build/css/ngToast-animations.min.css',
            'build/css/tree-control.css',
            'build/css/tree-control-attribute.css'
          ]
        }
      }
    },

    // concatenation + minification
    uglify: {
      options: {
        banner: '/*! <%= pkg.name %> <%= grunt.template.today("yyyy-mm-dd") %> */\n'
      },
      dev: {
        files: [{
          expand: true,
          src: ['build/js/ui-bootstrap.js', 'build/js/ui-bootstrap-tpls.js'],
          dest: 'build/js',
          cwd: '.',
          rename: function (dst, src) {
            return src.replace('.js', '.min.js');
          }
        }]
      },
      build: {
        src: [
            // These are concatenated in order in the final build file.
            // The order is important.
            '../common/build/js/jquery.min.js',
            'build/js/angular.min.js',
            'build/js/angular-animate.min.js',
            'build/js/angular-sanitize.min.js',
            'build/js/angular-route.min.js',
            'build/js/ui-bootstrap.min.js',
            'build/js/ui-bootstrap-tpls.js',
            'build/js/hotkeys.min.js',
            'build/js/angular-tree-control.js',
            'build/js/ngToast.min.js',
            'build/js/lovefield.min.js',
            'bulid/js/moment-with-locales.min.js',
            'build/js/moment-timezone-with-data.min.js',
            // NOTE: OpenSRF must be installed
            // XXX: Should not be hard-coded
            '/openils/lib/javascript/JSON_v1.js',
            '/openils/lib/javascript/opensrf.js',
            '/openils/lib/javascript/opensrf_ws.js',
            'services/core.js',
            'services/strings.js',
            'services/idl.js',
            'services/event.js',
            'services/net.js',
            'services/auth.js',
            'services/pcrud.js',
            'services/env.js',
            'services/org.js',
            'services/startup.js',
            'services/hatch.js',
            'services/print.js',
            'services/audio.js',
            'services/coresvc.js',
            'services/navbar.js',
            'services/ui.js',
            'services/date.js',
            'services/op_change.js',
            'services/file.js',
            'services/i18n.js'
        ],
        dest: 'build/js/<%= pkg.name %>.<%= pkg.version %>.min.js'
      },
    },

    // bare concat operation; useful for testing concat w/o minification
    // to more easily detect if concat order is incorrect
    concat: {
      options: {
       separator: ';'
      }
    },

    exec : {

      // Generate test/data/IDL2js.js for unit tests.
      // note: the output of this script is *not* part of the final build.
      idl2js : {
        command : 'cd test/data && perl idl2js.pl'
      },

      // Remove the unit test IDL2js.js file.  We don't need it after testing
      rmidl2js : {
        command : 'rm test/data/IDL2js.js'
      }
    },

    // unit tests configuration
    karma : {
      unit: {
        configFile: 'test/karma.conf.js'
        //background: true  // for now, visually babysit unit tests
      }
    }
  };

  // tell concat about our uglify build options (instead of repeating them)
  config.concat.build = config.uglify.build;

  // apply our configuration
  grunt.initConfig(config);

  // Load our modules
  grunt.loadNpmTasks('grunt-contrib-uglify');
  grunt.loadNpmTasks('grunt-contrib-concat');
  grunt.loadNpmTasks('grunt-contrib-copy');
  grunt.loadNpmTasks('grunt-contrib-cssmin');
  grunt.loadNpmTasks('grunt-karma');
  grunt.loadNpmTasks('grunt-exec');

  // note: "grunt concat" is not required 
  grunt.registerTask('build', ['copy', 'cssmin', 'uglify']);

  // test only, no minification
  grunt.registerTask('test', ['copy', 'exec:idl2js', 'karma:unit', 'exec:rmidl2js']);

  // note: "grunt concat" is not requried 
  grunt.registerTask('all', ['test', 'cssmin', 'uglify']);

};

// vim: ts=2:sw=2:softtabstop=2
