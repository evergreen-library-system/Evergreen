import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {EgCoreModule} from '@eg/core/core.module';
import {GridModule} from '@eg/share/grid/grid.module';
import {StringModule} from '@eg/share/string/string.module';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {AdminPageComponent} from './admin-page.component';
import {OrgFamilySelectModule} from '@eg/share/org-family-select/org-family-select.module';
import { TranslateComponent } from '@eg/share/translate/translate.component';


@NgModule({
    imports: [
        AdminPageComponent,
        EgCommonModule,
        EgCoreModule,
        StringModule,
        OrgFamilySelectModule,
        TranslateComponent,
        FmRecordEditorModule,
        GridModule
    ],
    exports: [
        OrgFamilySelectModule,
        AdminPageComponent
    ],
    providers: [
    ]
})

export class AdminPageModule { }

