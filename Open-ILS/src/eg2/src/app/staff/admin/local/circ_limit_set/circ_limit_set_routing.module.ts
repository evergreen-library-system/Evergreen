import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CircLimitSetComponent} from './circ_limit_set.component';
import {CircLimitSetEditComponent} from './circ_limit_set_edit.component';

const routes: Routes = [{
    path: '',
    component: CircLimitSetComponent
}, {
    path: ':id',
    component: CircLimitSetEditComponent
}];


@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CircLimitSetRoutingModule {}
