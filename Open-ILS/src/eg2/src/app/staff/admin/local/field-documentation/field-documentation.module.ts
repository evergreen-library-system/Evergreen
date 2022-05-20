import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {FieldDocumentationComponent} from './field-documentation.component';
import {FieldDocumentationRoutingModule} from './routing.module';

@NgModule({
    declarations: [
        FieldDocumentationComponent
    ],
    imports: [
        AdminCommonModule,
        FieldDocumentationRoutingModule
    ],
    exports: [],
    providers: []
})

export class FieldDocumentationModule {}
