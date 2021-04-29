import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CheckinComponent} from './checkin.component';

const routes: Routes = [{
    path: '',
    component: CheckinComponent
  }, {
    path: 'capture',
    component: CheckinComponent,
    data: {capture: true}
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CheckinRoutingModule {}
