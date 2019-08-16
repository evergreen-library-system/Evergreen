import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminServerRoutingModule} from './routing.module';
import {AdminServerSplashComponent} from './admin-server-splash.component';
import {OrgUnitTypeComponent} from './org-unit-type.component';
import {PrintTemplateComponent} from './print-template.component';
import {SampleDataService} from '@eg/share/util/sample-data.service';
import {PermGroupTreeComponent} from './perm-group-tree.component';
import {PermGroupMapDialogComponent} from './perm-group-map-dialog.component';

/* As it stands, all components defined under admin/server are
imported / declared in the admin/server base module.  This could
cause the module to baloon in size.  Consider moving non-auto-
generated UI's into lazy-loadable sub-mobules. */

@NgModule({
  declarations: [
      AdminServerSplashComponent,
      OrgUnitTypeComponent,
      PrintTemplateComponent,
      PermGroupTreeComponent,
      PermGroupMapDialogComponent
  ],
  imports: [
    AdminCommonModule,
    AdminServerRoutingModule,
    TreeModule
  ],
  exports: [
  ],
  providers: [
    SampleDataService
  ]
})

export class AdminServerModule {
}


