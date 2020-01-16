import {NgModule, ModuleWithProviders} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {AudioService} from '@eg/share/util/audio.service';
import {GridModule} from '@eg/share/grid/grid.module';
import {CatalogCommonModule} from '@eg/share/catalog/catalog-common.module';
import {StaffBannerComponent} from './share/staff-banner.component';
import {AccessKeyDirective} from '@eg/share/accesskey/accesskey.directive';
import {AccessKeyService} from '@eg/share/accesskey/accesskey.service';
import {AccessKeyInfoComponent} from '@eg/share/accesskey/accesskey-info.component';
import {OpChangeComponent} from '@eg/staff/share/op-change/op-change.component';
import {TitleComponent} from '@eg/share/title/title.component';
import {BucketDialogComponent} from '@eg/staff/share/buckets/bucket-dialog.component';
import {BibSummaryComponent} from '@eg/staff/share/bib-summary/bib-summary.component';
import {EgHelpPopoverComponent} from '@eg/share/eg-help-popover/eg-help-popover.component';
import {DatetimeValidatorDirective} from '@eg/share/validators/datetime_validator.directive';
import {MultiSelectComponent} from '@eg/share/multi-select/multi-select.component';
import {NotBeforeMomentValidatorDirective} from '@eg/share/validators/not_before_moment_validator.directive';
import {PatronBarcodeValidatorDirective} from '@eg/share/validators/patron_barcode_validator.directive';

/**
 * Imports the EG common modules and adds modules common to all staff UI's.
 */

@NgModule({
  declarations: [
    StaffBannerComponent,
    AccessKeyDirective,
    AccessKeyInfoComponent,
    TitleComponent,
    OpChangeComponent,
    BucketDialogComponent,
    BibSummaryComponent,
    EgHelpPopoverComponent,
    DatetimeValidatorDirective,
    MultiSelectComponent,
    NotBeforeMomentValidatorDirective,
    PatronBarcodeValidatorDirective,
  ],
  imports: [
    EgCommonModule,
    CommonWidgetsModule,
    GridModule,
    CatalogCommonModule
  ],
  exports: [
    EgCommonModule,
    CommonWidgetsModule,
    GridModule,
    CatalogCommonModule,
    StaffBannerComponent,
    AccessKeyDirective,
    AccessKeyInfoComponent,
    TitleComponent,
    OpChangeComponent,
    BucketDialogComponent,
    BibSummaryComponent,
    EgHelpPopoverComponent,
    DatetimeValidatorDirective,
    MultiSelectComponent,
    NotBeforeMomentValidatorDirective,
    PatronBarcodeValidatorDirective
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

