import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [{
  path: '',
  children : [
  { path: 'workstation',
   loadChildren: '@eg/staff/admin/workstation/routing.module#AdminWsRoutingModule'
  }, {
    path: 'server',
    loadChildren: '@eg/staff/admin/server/admin-server.module#AdminServerModule'
  }, {
    path: 'acq',
    loadChildren: '@eg/staff/admin/acq/admin-acq.module#AdminAcqModule'
  }]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AdminRoutingModule {}
