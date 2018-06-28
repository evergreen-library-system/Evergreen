import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [
  { path: 'vandelay',
    loadChildren: '@eg/staff/cat/vandelay/vandelay.module#VandelayModule'
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CatRoutingModule {}
