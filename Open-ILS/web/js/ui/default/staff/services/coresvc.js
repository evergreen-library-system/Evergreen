/**
 * egCore service
 *
 * Aggregates all core services into a container service.  This allows
 * use of core services without having to inject each individually.
 */

angular.module('egCoreMod')

.factory('egCore', 
       ['egIDL','egNet','egEnv','egOrg','egPCRUD','egEvent','egAuth',
        'egPerm','egHatch','egPrint','egStartup','egStrings',
function(egIDL , egNet , egEnv , egOrg , egPCRUD , egEvent , egAuth , 
         egPerm , egHatch , egPrint , egStartup , egStrings) {

    return {
        idl     : egIDL,
        net     : egNet,
        env     : egEnv,
        org     : egOrg,
        pcrud   : egPCRUD,
        evt     : egEvent,
        auth    : egAuth,
        perm    : egPerm,
        hatch   : egHatch,
        print   : egPrint,
        startup : egStartup,
        strings : egStrings
    };

}]);


