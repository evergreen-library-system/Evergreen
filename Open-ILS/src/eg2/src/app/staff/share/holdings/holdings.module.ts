import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldingsService} from './holdings.service';
import {MarkDamagedDialogComponent} from './mark-damaged-dialog.component';
import {MarkMissingDialogComponent} from './mark-missing-dialog.component';

@NgModule({
    declarations: [
      MarkDamagedDialogComponent,
      MarkMissingDialogComponent
    ],
    imports: [
        StaffCommonModule
    ],
    exports: [
      MarkDamagedDialogComponent,
      MarkMissingDialogComponent
    ],
    providers: [
        HoldingsService
    ]
})

export class HoldingsModule {}

