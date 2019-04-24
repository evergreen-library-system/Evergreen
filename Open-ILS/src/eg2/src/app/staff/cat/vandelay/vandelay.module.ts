import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CatalogCommonModule} from '@eg/share/catalog/catalog-common.module';
import {HttpClientModule} from '@angular/common/http';
import {TreeModule} from '@eg/share/tree/tree.module';
import {VandelayRoutingModule} from './routing.module';
import {VandelayService} from './vandelay.service';
import {VandelayComponent} from './vandelay.component';
import {ImportComponent} from './import.component';
import {ExportComponent} from './export.component';
import {QueueComponent} from './queue.component';
import {QueueListComponent} from './queue-list.component';
import {QueuedRecordComponent} from './queued-record.component';
import {QueuedRecordMatchesComponent} from './queued-record-matches.component';
import {DisplayAttrsComponent} from './display-attrs.component';
import {MergeProfilesComponent} from './merge-profiles.component';
import {HoldingsProfilesComponent} from './holdings-profiles.component';
import {QueueItemsComponent} from './queue-items.component';
import {RecordItemsComponent} from './record-items.component';
import {MatchSetListComponent} from './match-set-list.component';
import {MatchSetComponent} from './match-set.component';
import {MatchSetExpressionComponent} from './match-set-expression.component';
import {MatchSetQualityComponent} from './match-set-quality.component';
import {MatchSetNewPointComponent} from './match-set-new-point.component';
import {RecentImportsComponent} from './recent-imports.component';

@NgModule({
  declarations: [
    VandelayComponent,
    ImportComponent,
    ExportComponent,
    QueueComponent,
    QueueListComponent,
    QueuedRecordComponent,
    QueuedRecordMatchesComponent,
    DisplayAttrsComponent,
    MergeProfilesComponent,
    HoldingsProfilesComponent,
    QueueItemsComponent,
    RecordItemsComponent,
    MatchSetListComponent,
    MatchSetComponent,
    MatchSetExpressionComponent,
    MatchSetQualityComponent,
    MatchSetNewPointComponent,
    RecentImportsComponent
  ],
  imports: [
    TreeModule,
    StaffCommonModule,
    CatalogCommonModule,
    VandelayRoutingModule,
    HttpClientModule,
  ],
  providers: [
    VandelayService
  ]
})

export class VandelayModule {
}
