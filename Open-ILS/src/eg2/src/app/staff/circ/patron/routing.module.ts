import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {PatronComponent} from './patron.component';

const routes: Routes = [{
    path: '',
    pathMatch: 'full',
    redirectTo: 'search'
  }, {
    path: 'event-log',
    loadChildren: () =>
      import('./event-log/event-log.module').then(m => m.EventLogModule)
  }, {
    path: 'search',
    component: PatronComponent
  }, {
    path: 'bcsearch',
    component: PatronComponent
  }, {
    path: ':id/:tab',
    component: PatronComponent,
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class PatronRoutingModule {}
