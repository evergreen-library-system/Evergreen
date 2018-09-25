import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [
  { path: 'bcsearch',
    loadChildren: '@eg/staff/circ/patron/bcsearch/bcsearch.module#BcSearchModule'
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CircPatronRoutingModule {}
