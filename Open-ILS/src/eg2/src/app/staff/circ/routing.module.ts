import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [
  { path: 'patron',
    loadChildren: '@eg/staff/circ/patron/routing.module#CircPatronRoutingModule'
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CircRoutingModule {}
