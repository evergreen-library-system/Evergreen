
import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {HoldMatrixMatchpointComponent} from './hold-matrix-matchpoint.component';
const routes: Routes = [{
    path: '',
    component: HoldMatrixMatchpointComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class HoldMatrixMatchpointRoutingModule {}
