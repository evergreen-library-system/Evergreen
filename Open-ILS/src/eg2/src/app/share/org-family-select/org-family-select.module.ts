import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {EgCoreModule} from '@eg/core/core.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {OrgFamilySelectComponent} from './org-family-select.component';
import {ReactiveFormsModule} from '@angular/forms';

@NgModule({
    imports: [
        EgCommonModule,
        EgCoreModule,
        CommonWidgetsModule,
        OrgFamilySelectComponent,
        ReactiveFormsModule
    ],
    exports: [
        OrgFamilySelectComponent
    ]
})

export class OrgFamilySelectModule { }

