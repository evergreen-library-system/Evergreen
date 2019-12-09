import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {CircMatrixMatchpointRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {CircMatrixMatchpointComponent} from './circ-matrix-matchpoint.component'
import {LinkedCircLimitSetsComponent} from './linked-circ-limit-sets.component'

@NgModule({
  declarations: [
    CircMatrixMatchpointComponent,
    LinkedCircLimitSetsComponent
  ],
  imports: [
    AdminCommonModule,
    CircMatrixMatchpointRoutingModule,
    TreeModule
  ],
  exports: [
  ],
  providers: [
  ]
})

export class CircMatrixMathpointModule {
}


