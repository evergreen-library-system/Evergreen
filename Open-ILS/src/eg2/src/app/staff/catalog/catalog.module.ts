import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CatalogCommonModule} from '@eg/share/catalog/catalog-common.module';
import {CatalogRoutingModule} from './routing.module';
import {CatalogComponent} from './catalog.component';
import {SearchFormComponent} from './search-form.component';
import {ResultsComponent} from './result/results.component';
import {RecordComponent} from './record/record.component';
import {CopiesComponent} from './record/copies.component';
import {ResultPaginationComponent} from './result/pagination.component';
import {ResultFacetsComponent} from './result/facets.component';
import {ResultRecordComponent} from './result/record.component';
import {StaffCatalogService} from './catalog.service';
import {RecordPaginationComponent} from './record/pagination.component';
import {RecordActionsComponent} from './record/actions.component';
import {HoldingsService} from '@eg/staff/share/holdings.service';

@NgModule({
  declarations: [
    CatalogComponent,
    ResultsComponent,
    RecordComponent,
    CopiesComponent,
    SearchFormComponent,
    ResultRecordComponent,
    ResultFacetsComponent,
    ResultPaginationComponent,
    RecordPaginationComponent,
    RecordActionsComponent
  ],
  imports: [
    StaffCommonModule,
    CatalogCommonModule,
    CatalogRoutingModule
  ],
  providers: [
    StaffCatalogService,
    HoldingsService
  ]
})

export class CatalogModule {

}
