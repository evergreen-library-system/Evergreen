import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {TreeModule} from '@eg/share/tree/tree.module';
import {CodedValueMapsComponent} from './coded-value-maps.component';
import {CompositeDefComponent} from './composite-def.component';
import {CompositeNewPointComponent} from './composite-new.component';
import {CodedValueMapsRoutingModule} from './coded-value-maps-routing.module';
import {AdminPageModule} from '@eg/staff/share/admin-page/admin-page.module';

@NgModule({
    declarations: [
        CodedValueMapsComponent,
        CompositeDefComponent,
        CompositeNewPointComponent,
    ],
    imports: [
        StaffCommonModule,
        FmRecordEditorModule,
        TreeModule,
        AdminPageModule,
        CodedValueMapsRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class CodedValueMapsModule {
}
