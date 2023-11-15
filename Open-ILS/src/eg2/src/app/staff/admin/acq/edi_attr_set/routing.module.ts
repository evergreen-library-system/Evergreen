import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {EdiAttrSetsComponent} from './edi-attr-sets.component';

const routes: Routes = [{
    path: '',
    component: EdiAttrSetsComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class EdiAttrSetsRoutingModule {}
