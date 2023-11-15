import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {DistributionFormulasComponent} from './distribution-formulas.component';

const routes: Routes = [{
    path: '',
    component: DistributionFormulasComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class DistributionFormulasRoutingModule {}
