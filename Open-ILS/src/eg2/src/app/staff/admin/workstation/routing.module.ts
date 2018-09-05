import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [{
    path: 'workstations',
    loadChildren: '@eg/staff/admin/workstation/workstations/workstations.module#ManageWorkstationsModule'
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AdminWsRoutingModule {}
