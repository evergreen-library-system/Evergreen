import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {VolCopyComponent} from './volcopy.component';

const routes: Routes = [{
    path: ':tab/:target/:target_id',
    component: VolCopyComponent
  /*
  }, {
    path: 'templates'
    component: VolCopyComponent
  }, {
    path: 'configure'
    component: VolCopyComponent
    */
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class VolCopyRoutingModule {}

