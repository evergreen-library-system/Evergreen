module.exports = function(grunt) {

  // Project configuration.
  var config = { 
    pkg: grunt.file.readJSON('package.json'),

    // copy the files we care about from bower-fetched dependencies
    // into our build directory
    copy: {

      js : {
        files: [{ 
          dest: 'build/js/', 
          flatten: true,
          filter: 'isFile',
          expand : true,
          src: [
            'bower_components/angular/angular.min.js',
            'bower_components/angular/angular.min.js.map',
            'bower_components/angular-animate/angular-animate.min.js',
            'bower_components/angular-animate/angular-animate.min.js.map',
            'bower_components/angular-sanitize/angular-sanitize.min.js',
            'bower_components/angular-sanitize/angular-sanitize.min.js.map',
            'bower_components/angular-route/angular-route.min.js',
            'bower_components/angular-route/angular-route.min.js.map',
            'bower_components/angular-bootstrap/ui-bootstrap.min.js',
            'bower_components/angular-bootstrap/ui-bootstrap-tpls.min.js',
            'bower_components/angular-hotkeys/build/hotkeys.min.js',
            'bower_components/angular-file-saver/dist/angular-file-saver.bundle.min.js',
            'bower_components/angular-location-update/angular-location-update.min.js',
            'bower_components/angular-tree-control/angular-tree-control.js',
            'bower_components/ngtoast/dist/ngToast.min.js',
            'bower_components/jquery/dist/jquery.min.js',
            'bower_components/angular-cookies/angular-cookies.min.js',
            'bower_components/angular-cookies/angular-cookies.min.js.map',
            'bower_components/iframe-resizer/js/iframeResizer.min.js',
            'bower_components/iframe-resizer/js/iframeResizer.map',
            'bower_components/iframe-resizer/js/iframeResizer.contentWindow.min.js',
            'bower_components/angular-order-object-by/src/ng-order-object-by.js'
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
            'bower_components/angular-hotkeys/build/hotkeys.min.css',
            'bower_components/bootstrap/dist/css/bootstrap.min.css', 
            'bower_components/ngtoast/dist/ngToast.min.css',
            'bower_components/ngtoast/dist/ngToast-animations.min.css',
            'bower_components/angular-tree-control/css/tree-control.css',
            'bower_components/angular-tree-control/css/tree-control-attribute.css',
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
            'bower_components/bootstrap/dist/fonts/glyphicons-halflings-regular.eot',
            'bower_components/bootstrap/dist/fonts/glyphicons-halflings-regular.svg',
            'bower_components/bootstrap/dist/fonts/glyphicons-halflings-regular.ttf',
            'bower_components/bootstrap/dist/fonts/glyphicons-halflings-regular.woff'
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
            'bower_components/angular-tree-control/images/sample.png',
            'bower_components/angular-tree-control/images/node-opened-2.png',
            'bower_components/angular-tree-control/images/folder.png',
            'bower_components/angular-tree-control/images/node-closed.png',
            'bower_components/angular-tree-control/images/node-closed-light.png',
            'bower_components/angular-tree-control/images/node-opened.png',
            'bower_components/angular-tree-control/images/node-opened-light.png',
            'bower_components/angular-tree-control/images/folder-closed.png',
            'bower_components/angular-tree-control/images/node-closed-2.png',
            'bower_components/angular-tree-control/images/file.png'
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
            'build/css/tree-control-attribute.css',
          ]
        }
      }
    },

    // concatenation + minification
    uglify: {
      options: {
        banner: '/*! <%= pkg.name %> <%= grunt.template.today("yyyy-mm-dd") %> */\n'
      },
      build: {
        src: [
            // These are concatenated in order in the final build file.
            // The order is important.
            'build/js/jquery.min.js',
            'build/js/angular.min.js',
            'build/js/angular-animate.min.js',
            'build/js/angular-sanitize.min.js',
            'build/js/angular-route.min.js',
            'build/js/ui-bootstrap.min.js',
            'build/js/ui-bootstrap-tpls.min.js',
            'build/js/hotkeys.min.js',
            'build/js/angular-tree-control.js',
            'build/js/ngToast.min.js',
            // NOTE: OpenSRF must be installed
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
            'services/statusbar.js',
            'services/ui.js',
            'services/date.js',
            'services/op_change.js',
        ],
        dest: 'build/js/<%= pkg.name %>.<%= pkg.version %>.min.js'
      }
    },

    // bare concat operation; useful for testing concat w/o minification
    // to more easily detect if concat order is incorrect
    concat: {
      options: {
       separator: ';',
      }
    },

    exec : {

      // Generate test/data/IDL2js.js for unit tests.
      // note: the output of this script is *not* part of the final build.
      idl2js : {
        command : 'cd test/data && perl idl2js.pl',
      },

      // Remove the unit test IDL2js.js file.  We don't need it after testing
      rmidl2js : {
        command : 'rm test/data/IDL2js.js',
      }
    },

    // unit tests configuration
    karma : {
      unit: {
        configFile: 'test/karma.conf.js',
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

  // note: "grunt concat" is not requried 
  grunt.registerTask('build', ['copy', 'cssmin', 'uglify']);

  // test only, no minification
  grunt.registerTask('test', ['copy', 'exec:idl2js', 'karma:unit', 'exec:rmidl2js']);

  // note: "grunt concat" is not requried 
  grunt.registerTask('all', ['test', 'cssmin', 'uglify']);

};

// vim: ts=2:sw=2:softtabstop=2
