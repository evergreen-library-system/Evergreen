import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {FieldDocumentationComponent} from './field-documentation.component';
const routes: Routes = [{
    path: '',
    component: FieldDocumentationComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class FieldDocumentationRoutingModule {}
