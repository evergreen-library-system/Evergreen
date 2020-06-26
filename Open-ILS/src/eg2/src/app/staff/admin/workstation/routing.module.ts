import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [{
    path: 'workstations',
    loadChildren: () =>
      import('./workstations/workstations.module').then(m => m.ManageWorkstationsModule)
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AdminWsRoutingModule {}
