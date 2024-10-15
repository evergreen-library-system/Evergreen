import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {VolCopyRoutingModule} from './routing.module';
import {VolCopyComponent} from './volcopy.component';
import {ComboboxLabelDedupePipe, VolEditComponent} from './vol-edit.component';
import {VolCopyService} from './volcopy.service';
import {CopyAttrsComponent} from './copy-attrs.component';
import {ItemLocationSelectModule} from '@eg/share/item-location-select/item-location-select.module';
import {VolCopyConfigComponent} from './config.component';
import {VolCopyPermissionDialogComponent} from './vol-copy-permission-dialog.component';

@NgModule({
    declarations: [
        VolCopyComponent,
        VolEditComponent,
        CopyAttrsComponent,
        VolCopyConfigComponent,
        VolCopyPermissionDialogComponent,
        ComboboxLabelDedupePipe
    ],
    imports: [
        StaffCommonModule,
        CommonWidgetsModule,
        HoldingsModule,
        VolCopyRoutingModule,
        ItemLocationSelectModule
    ],
    exports: [
        VolCopyPermissionDialogComponent
    ],
    providers: [
        VolCopyService
    ]
})

export class VolCopyModule {
}
