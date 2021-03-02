import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AdminAcqSplashComponent} from './admin-acq-splash.component';
import {BasicAdminPageComponent} from '@eg/staff/admin/basic-admin-page.component';
import {ClaimingAdminComponent} from './claiming-admin.component';

const routes: Routes = [{
    path: 'splash',
    component: AdminAcqSplashComponent
}, {
    path: 'edi_account',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'acq',
        table: 'edi_account',
        fieldOrder: 'id,label,provider,owner,account,vendacct,vendcode,last_activity,host,username,password,path,in_dir,use_attrs,attr_set',
        readonlyFields: 'last_activity'
    }]
}, {
    path: 'claiming',
    component: ClaimingAdminComponent
}, {
    path: 'claim_event_type',
    redirectTo: 'claiming' // from legacy auto-generated admin page
}, {
    path: 'claim_policy',
    redirectTo: 'claiming' // from legacy auto-generated admin page
}, {
    path: 'claim_policy_action',
    redirectTo: 'claiming' // from legacy auto-generated admin page
}, {
    path: 'claim_type',
    redirectTo: 'claiming' // from legacy auto-generated admin page
}, {
    path: ':table',
    component: BasicAdminPageComponent,
    // All ACQ admin pages cover data in the acq.* schema.  No need to
    // duplicate it within the URL path.  Pass it manually instead.
    data: [{schema: 'acq'}]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AdminAcqRoutingModule {}
