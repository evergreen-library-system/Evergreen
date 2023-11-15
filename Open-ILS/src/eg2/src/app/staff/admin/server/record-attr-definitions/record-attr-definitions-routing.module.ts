import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {RecordAttrDefinitionsComponent} from './record-attr-definitions.component';

const routes: Routes = [{
    path: '',
    component: RecordAttrDefinitionsComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class RecordAttrDefinitionsRoutingModule {}
