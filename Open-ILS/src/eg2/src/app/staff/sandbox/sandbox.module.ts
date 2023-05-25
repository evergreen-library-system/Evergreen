import {NgModule} from '@angular/core';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {TranslateModule} from '@eg/share/translate/translate.module';
import {SandboxRoutingModule} from './routing.module';
import {SandboxComponent} from './sandbox.component';
import {ReactiveFormsModule} from '@angular/forms';
import {SampleDataService} from '@eg/share/util/sample-data.service';
import {OrgFamilySelectModule} from '@eg/share/org-family-select/org-family-select.module';
import {ItemLocationSelectModule} from '@eg/share/item-location-select/item-location-select.module';
import {PatronModule} from '@eg/staff/share/patron/patron.module';
import {Z3950SearchModule} from '@eg/staff/share/z3950-search/z3950-search.module';

@NgModule({
    declarations: [
        SandboxComponent
    ],
    imports: [
        StaffCommonModule,
        TranslateModule,
        FmRecordEditorModule,
        OrgFamilySelectModule,
        ItemLocationSelectModule,
        SandboxRoutingModule,
        ReactiveFormsModule,
        PatronModule,
        Z3950SearchModule
    ],
    providers: [
        SampleDataService
    ]
})

export class SandboxModule {

}
