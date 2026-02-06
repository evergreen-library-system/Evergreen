
import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {CircMatrixMatchpointRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {CircMatrixMatchpointComponent} from './circ-matrix-matchpoint.component';
import {LinkedCircLimitSetsComponent} from './linked-circ-limit-sets.component';
import {CircMatrixMatchpointDialogComponent} from './circ-matrix-matchpoint-dialog.component';

@NgModule({
    imports: [
        CircMatrixMatchpointComponent,
        LinkedCircLimitSetsComponent,
        CircMatrixMatchpointDialogComponent,
        AdminCommonModule,
        CircMatrixMatchpointRoutingModule,
        TreeModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class CircMatrixMatchpointModule {
}


