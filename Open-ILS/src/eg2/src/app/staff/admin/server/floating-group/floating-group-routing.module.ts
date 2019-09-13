import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {EditFloatingGroupComponent} from './edit-floating-group.component';
import {FloatingGroupComponent} from './floating-group.component';

const routes: Routes = [{
    path: ':id',
    component: EditFloatingGroupComponent
  }, {
    path: '',
    component: FloatingGroupComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class FloatingGroupRoutingModule {}
