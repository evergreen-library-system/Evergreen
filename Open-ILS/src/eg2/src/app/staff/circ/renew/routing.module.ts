import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {RenewComponent} from './renew.component';

const routes: Routes = [{
    path: '',
    component: RenewComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class RenewRoutingModule {}
