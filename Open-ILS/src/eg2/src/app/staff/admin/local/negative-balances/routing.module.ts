import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {NegativeBalancesComponent} from './list.component';

const routes: Routes = [{
    path: '',
    component: NegativeBalancesComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class NegativeBalancesRoutingModule {}
