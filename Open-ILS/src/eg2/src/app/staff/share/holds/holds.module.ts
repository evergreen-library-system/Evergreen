import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {HoldsService} from './holds.service';
import {HoldsGridComponent} from './grid.component';
import {HoldDetailComponent} from './detail.component';
import {HoldManageComponent} from './manage.component';
import {HoldRetargetDialogComponent} from './retarget-dialog.component';
import {HoldTransferDialogComponent} from './transfer-dialog.component';
import {HoldTransferViaBibsDialogComponent} from './transfer-via-bibs-dialog.component';
import {HoldCancelDialogComponent} from './cancel-dialog.component';
import {HoldManageDialogComponent} from './manage-dialog.component';
import {HoldNoteDialogComponent} from './note-dialog.component';
import {HoldNotifyDialogComponent} from './notify-dialog.component';
import {HoldCopyLocationsDialogComponent} from './copy-locations-dialog.component';
import {WorkLogModule} from '@eg/staff/share/worklog/worklog.module';

@NgModule({
    imports: [
        HoldCancelDialogComponent,
        HoldCopyLocationsDialogComponent,
        HoldDetailComponent,
        HoldManageComponent,
        HoldManageDialogComponent,
        HoldNoteDialogComponent,
        HoldNotifyDialogComponent,
        HoldRetargetDialogComponent,
        HoldsGridComponent,
        HoldTransferDialogComponent,
        HoldTransferViaBibsDialogComponent,
        StaffCommonModule,
        HoldingsModule,
        WorkLogModule
    ],
    exports: [
        HoldsGridComponent,
        HoldDetailComponent,
        HoldManageComponent,
        HoldRetargetDialogComponent,
        HoldTransferDialogComponent,
        HoldTransferViaBibsDialogComponent,
        HoldCancelDialogComponent,
        HoldManageDialogComponent,
        HoldCopyLocationsDialogComponent
    ],
    providers: [
        HoldsService
    ]
})

export class HoldsModule {}
