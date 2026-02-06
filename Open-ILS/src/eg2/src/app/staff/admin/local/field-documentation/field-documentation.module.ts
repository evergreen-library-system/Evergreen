import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {FieldDocumentationComponent} from './field-documentation.component';
import {FieldDocumentationRoutingModule} from './routing.module';

@NgModule({
    imports: [
        AdminCommonModule,
        FieldDocumentationComponent,
        FieldDocumentationRoutingModule
    ],
    exports: [],
    providers: []
})

export class FieldDocumentationModule {}
