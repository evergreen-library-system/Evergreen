import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {AudioService} from '@eg/share/util/audio.service';
import {TitleComponent} from '@eg/share/title/title.component';
import {PatronModule} from '@eg/staff/share/patron/patron.module';

import {SckoComponent} from './scko.component';
import {SckoRoutingModule} from './routing.module';
import {SckoService} from './scko.service';
import {SckoBannerComponent} from './banner.component';
import {SckoSummaryComponent} from './summary.component';
import {SckoCheckoutComponent} from './checkout.component';
import {SckoItemsComponent} from './items.component';
import {SckoHoldsComponent} from './holds.component';
import {SckoFinesComponent} from './fines.component';
import {ForceReloadService} from '@eg/share/util/force-reload.service';

@NgModule({
  declarations: [
    SckoComponent,
    SckoBannerComponent,
    SckoSummaryComponent,
    SckoCheckoutComponent,
    SckoItemsComponent,
    SckoHoldsComponent,
    SckoFinesComponent
  ],
  imports: [
    EgCommonModule,
    CommonWidgetsModule,
    PatronModule,
    SckoRoutingModule
  ],
  providers: [
    SckoService,
    AudioService,
    ForceReloadService
  ]
})

export class SckoModule {}

