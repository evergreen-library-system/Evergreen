import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CircMatrixMatchpointComponent} from './circ-matrix-matchpoint.component';
const routes: Routes = [{
    path: '',
    component: CircMatrixMatchpointComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CircMatrixMatchpointRoutingModule {}
