import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {TriggersComponent} from './triggers.component';
import {EditEventDefinitionComponent} from './trigger-edit.component';

const routes: Routes = [{
    path: '',
    component: TriggersComponent
}, {
    path: ':id',
    component: EditEventDefinitionComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class TriggersRoutingModule {
}
