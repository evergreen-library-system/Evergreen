
import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {HoldMatrixMatchpointRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {HoldMatrixMatchpointComponent} from './hold-matrix-matchpoint.component';
import {HoldMatrixMatchpointDialogComponent} from './hold-matrix-matchpoint-dialog.component';

@NgModule({
    declarations: [
        HoldMatrixMatchpointComponent,
        HoldMatrixMatchpointDialogComponent
    ],
    imports: [
        AdminCommonModule,
        HoldMatrixMatchpointRoutingModule,
        TreeModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class HoldMatrixMatchpointModule {
}


