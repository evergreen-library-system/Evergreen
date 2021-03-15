import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {PatronComponent} from './patron.component';
import {BcSearchComponent} from './bcsearch.component';
import {PatronResolver} from './resolver.service';
import {TestPatronPasswordComponent} from './test-password.component';

const routes: Routes = [{
    path: '',
    pathMatch: 'full',
    redirectTo: 'search'
  }, {
    path: 'event-log',
    loadChildren: () =>
      import('./event-log/event-log.module').then(m => m.EventLogModule)
  }, {
    path: 'credentials',
    component: TestPatronPasswordComponent
  }, {
    path: 'search',
    component: PatronComponent,
    resolve: {resolver : PatronResolver}
  }, {
    path: 'bcsearch',
    component: BcSearchComponent
  }, {
    path: 'bcsearch/:barcode',
    component: BcSearchComponent
  }, {
    path: ':id',
    redirectTo: ':id/checkout'
  }, {
    path: ':id/:tab/:xactId/statement',
    component: PatronComponent,
    resolve: {resolver : PatronResolver}
  }, {
    path: ':id/:tab',
    component: PatronComponent,
    resolve: {resolver : PatronResolver}
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class PatronRoutingModule {}
