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
    path: 'booking',
    loadChildren : '@eg/staff/booking/booking.module#BookingModule'
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
    loadChildren : '@eg/staff/circ/routing.module#CircRoutingModule'
  }, {
    path: 'cat',
    loadChildren : '@eg/staff/cat/routing.module#CatRoutingModule'
  }, {
    path: 'catalog',
    loadChildren : '@eg/staff/catalog/catalog.module#CatalogModule'
  }, {
    path: 'sandbox',
    loadChildren : '@eg/staff/sandbox/sandbox.module#SandboxModule'
  }, {
    path: 'admin',
    loadChildren : '@eg/staff/admin/routing.module#AdminRoutingModule'
  }]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: [StaffResolver]
})

export class StaffRoutingModule {}

