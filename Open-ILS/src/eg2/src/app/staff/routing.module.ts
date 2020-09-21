import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {StaffResolver} from './resolver.service';
import {StaffComponent} from './staff.component';
import {StaffLoginComponent} from './login.component';
import {StaffSplashComponent} from './splash.component';
import {AboutComponent} from './about.component';

// Not using 'canActivate' because it's called before all resolvers,
// even the parent resolver, but the resolvers parse the IDL, load settings,
// etc.  Chicken, meet egg.

const routes: Routes = [{
  path: '',
  component: StaffComponent,
  resolve: {staffResolver : StaffResolver},
  children: [{
    path: '',
    redirectTo: 'splash',
    pathMatch: 'full',
  }, {
    path: 'acq',
    loadChildren: () =>
      import('@eg/staff/acq/routing.module').then(m => m.AcqRoutingModule)
  }, {
    path: 'booking',
    loadChildren: () =>
      import('./booking/booking.module').then(m => m.BookingModule)
  }, {
    path: 'about',
    component: AboutComponent
  }, {
    path: 'login',
    component: StaffLoginComponent
  }, {
    path: 'splash',
    component: StaffSplashComponent
  }, {
    path: 'circ',
    loadChildren: () =>
      import('./circ/routing.module').then(m => m.CircRoutingModule)
  }, {
    path: 'cat',
    loadChildren: () =>
      import('./cat/cat.module').then(m => m.CatModule)
  }, {
    path: 'catalog',
    loadChildren: () =>
      import('./catalog/catalog.module').then(m => m.CatalogModule)
  }, {
    path: 'sandbox',
    loadChildren: () =>
      import('./sandbox/sandbox.module').then(m => m.SandboxModule)
  }, {
    path: 'hopeless',
    loadChildren: () =>
      import('@eg/staff/hopeless/hopeless.module').then(m => m.HopelessModule)
  }, {
    path: 'admin',
    loadChildren: () =>
      import('./admin/routing.module').then(m => m.AdminRoutingModule)
  }]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: [StaffResolver]
})

export class StaffRoutingModule {}

