import {NgModule, ModuleWithProviders} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {AudioService} from '@eg/share/util/audio.service';
import {GridModule} from '@eg/share/grid/grid.module';
import {StaffBannerComponent} from './share/staff-banner.component';
import {OrgFamilySelectComponent} from '@eg/share/org-family-select/org-family-select.component';
import {AccessKeyDirective} from '@eg/share/accesskey/accesskey.directive';
import {AccessKeyService} from '@eg/share/accesskey/accesskey.service';
import {AccessKeyInfoComponent} from '@eg/share/accesskey/accesskey-info.component';
import {OpChangeComponent} from '@eg/staff/share/op-change/op-change.component';
import {TitleComponent} from '@eg/share/title/title.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {BucketDialogComponent} from '@eg/staff/share/buckets/bucket-dialog.component';
import {BibSummaryComponent} from '@eg/staff/share/bib-summary/bib-summary.component';
import {TranslateComponent} from '@eg/staff/share/translate/translate.component';
import {AdminPageComponent} from '@eg/staff/share/admin-page/admin-page.component';
import {EgHelpPopoverComponent} from '@eg/share/eg-help-popover/eg-help-popover.component';
import {DatetimeValidatorDirective} from '@eg/share/validators/datetime_validator.directive';
import {ReactiveFormsModule} from '@angular/forms';
import {MultiSelectComponent} from '@eg/share/multi-select/multi-select.component';

/**
 * Imports the EG common modules and adds modules common to all staff UI's.
 */

@NgModule({
  declarations: [
    StaffBannerComponent,
    OrgFamilySelectComponent,
    AccessKeyDirective,
    AccessKeyInfoComponent,
    TitleComponent,
    OpChangeComponent,
    FmRecordEditorComponent,
    BucketDialogComponent,
    BibSummaryComponent,
    TranslateComponent,
    AdminPageComponent,
    EgHelpPopoverComponent,
    DatetimeValidatorDirective,
    MultiSelectComponent
  ],
  imports: [
    EgCommonModule,
    CommonWidgetsModule,
    GridModule
  ],
  exports: [
    EgCommonModule,
    CommonWidgetsModule,
    GridModule,
    StaffBannerComponent,
    OrgFamilySelectComponent,
    AccessKeyDirective,
    AccessKeyInfoComponent,
    TitleComponent,
    OpChangeComponent,
    FmRecordEditorComponent,
    BucketDialogComponent,
    BibSummaryComponent,
    TranslateComponent,
    AdminPageComponent,
    EgHelpPopoverComponent,
    DatetimeValidatorDirective,
    MultiSelectComponent
  ]
})

export class StaffCommonModule {
    static forRoot(): ModuleWithProviders {
        return {
            ngModule: StaffCommonModule,
            providers: [ // Export staff-wide services
                AccessKeyService,
                AudioService
            ]
        };
    }
}

