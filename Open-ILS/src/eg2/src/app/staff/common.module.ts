import {NgModule, ModuleWithProviders} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {AudioService} from '@eg/share/util/audio.service';
import {GridModule} from '@eg/share/grid/grid.module';
import {StaffBannerComponent} from './share/staff-banner.component';
import {ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {ComboboxEntryComponent} from '@eg/share/combobox/combobox-entry.component';
import {OrgSelectComponent} from '@eg/share/org-select/org-select.component';
import {AccessKeyDirective} from '@eg/share/accesskey/accesskey.directive';
import {AccessKeyService} from '@eg/share/accesskey/accesskey.service';
import {AccessKeyInfoComponent} from '@eg/share/accesskey/accesskey-info.component';
import {OpChangeComponent} from '@eg/staff/share/op-change/op-change.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {ToastComponent} from '@eg/share/toast/toast.component';
import {StringComponent} from '@eg/share/string/string.component';
import {StringService} from '@eg/share/string/string.service';
import {TitleComponent} from '@eg/share/title/title.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {DateSelectComponent} from '@eg/share/date-select/date-select.component';
import {BucketDialogComponent} from '@eg/staff/share/buckets/bucket-dialog.component';
import {BibSummaryComponent} from '@eg/staff/share/bib-summary/bib-summary.component';
import {TranslateComponent} from '@eg/staff/share/translate/translate.component';
import {AdminPageComponent} from '@eg/staff/share/admin-page/admin-page.component';

/**
 * Imports the EG common modules and adds modules common to all staff UI's.
 */

@NgModule({
  declarations: [
    StaffBannerComponent,
    ComboboxComponent,
    ComboboxEntryComponent,
    OrgSelectComponent,
    AccessKeyDirective,
    AccessKeyInfoComponent,
    ToastComponent,
    StringComponent,
    TitleComponent,
    OpChangeComponent,
    FmRecordEditorComponent,
    DateSelectComponent,
    BucketDialogComponent,
    BibSummaryComponent,
    TranslateComponent,
    AdminPageComponent
  ],
  imports: [
    EgCommonModule,
    GridModule
  ],
  exports: [
    EgCommonModule,
    GridModule,
    StaffBannerComponent,
    ComboboxComponent,
    ComboboxEntryComponent,
    OrgSelectComponent,
    AccessKeyDirective,
    AccessKeyInfoComponent,
    ToastComponent,
    StringComponent,
    TitleComponent,
    OpChangeComponent,
    FmRecordEditorComponent,
    DateSelectComponent,
    BucketDialogComponent,
    BibSummaryComponent,
    TranslateComponent,
    AdminPageComponent
  ]
})

export class StaffCommonModule {
    static forRoot(): ModuleWithProviders {
        return {
            ngModule: StaffCommonModule,
            providers: [ // Export staff-wide services
                AccessKeyService,
                AudioService,
                StringService,
                ToastService
            ]
        };
    }
}

