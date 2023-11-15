import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CodedValueMapsComponent} from './coded-value-maps.component';
import {CompositeDefComponent} from './composite-def.component';

const routes: Routes = [{
    path: '',
    component: CodedValueMapsComponent
}, {
    path: 'composite_def/:id',
    component: CompositeDefComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class CodedValueMapsRoutingModule {}
