import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {OrgUnitComponent} from './org-unit.component';

// Since org-unit admin has its own module with page-level components,
// it needs its own routing module as well to define which component
// to display at page load time.

const routes: Routes = [{
    path: '',
    component: OrgUnitComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class OrgUnitRoutingModule {}
