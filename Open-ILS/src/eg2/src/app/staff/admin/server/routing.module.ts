import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AdminServerSplashComponent} from './admin-server-splash.component';
import {BasicAdminPageComponent} from '@eg/staff/admin/basic-admin-page.component';

const routes: Routes = [{
    path: 'splash',
    component: AdminServerSplashComponent
}, {
    path: ':schema/:table',
    component: BasicAdminPageComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AdminServerRoutingModule {}
