import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {HoldsService} from './holds.service';
import {HoldsGridComponent} from './grid.component';
import {HoldDetailComponent} from './detail.component';
import {HoldManageComponent} from './manage.component';
import {HoldRetargetDialogComponent} from './retarget-dialog.component';
import {HoldTransferDialogComponent} from './transfer-dialog.component';
import {HoldCancelDialogComponent} from './cancel-dialog.component';
import {HoldManageDialogComponent} from './manage-dialog.component';
import {HoldNoteDialogComponent} from './note-dialog.component';
import {HoldNotifyDialogComponent} from './notify-dialog.component';
import {ItemLocationSelectModule} from '@eg/share/item-location-select/item-location-select.module';

@NgModule({
    declarations: [
        HoldsGridComponent,
        HoldDetailComponent,
        HoldManageComponent,
        HoldRetargetDialogComponent,
        HoldTransferDialogComponent,
        HoldCancelDialogComponent,
        HoldManageDialogComponent,
        HoldNoteDialogComponent,
        HoldNotifyDialogComponent
    ],
    imports: [
        StaffCommonModule,
        ItemLocationSelectModule,
        HoldingsModule
    ],
    exports: [
        HoldsGridComponent,
        HoldDetailComponent,
        HoldManageComponent,
        HoldRetargetDialogComponent,
        HoldTransferDialogComponent,
        HoldCancelDialogComponent,
        HoldManageDialogComponent
    ],
    providers: [
        HoldsService
    ]
})

export class HoldsModule {}
