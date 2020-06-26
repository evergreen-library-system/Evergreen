import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [{
  path: '',
  children : [{
    path: 'workstation',
    loadChildren: () =>
      import('./workstation/routing.module').then(m => m.AdminWsRoutingModule)
  }, {
    path: 'server',
    loadChildren: () =>
      import('./server/admin-server.module').then(m => m.AdminServerModule)
  }, {
    path: 'local',
    loadChildren: () =>
      import('./local/admin-local.module').then(m => m.AdminLocalModule)
  }, {
    path: 'acq',
    loadChildren: () =>
      import('./acq/admin-acq.module').then(m => m.AdminAcqModule)
  }, {
    path: 'booking',
    loadChildren: () =>
      import('./booking/admin-booking.module').then(m => m.AdminBookingModule)
  }]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AdminRoutingModule {}
