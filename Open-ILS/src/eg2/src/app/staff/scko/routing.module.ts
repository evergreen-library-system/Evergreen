import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {SckoComponent} from './scko.component';
import {SckoCheckoutComponent} from './checkout.component';
import {SckoItemsComponent} from './items.component';
import {SckoHoldsComponent} from './holds.component';
import {SckoFinesComponent} from './fines.component';

const routes: Routes = [{
  path: '',
  component: SckoComponent,
  children: [{
    path: '',
    component: SckoCheckoutComponent
  }, {
    path: 'items',
    component: SckoItemsComponent
   }, {
    path: 'holds',
    component: SckoHoldsComponent
   }, {
    path: 'fines',
    component: SckoFinesComponent
 }]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class SckoRoutingModule {}

