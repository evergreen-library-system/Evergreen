import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {AuthorityRoutingModule} from './routing.module';
import {MarcEditModule} from '@eg/staff/share/marc-edit/marc-edit.module';
import {AuthorityMarcEditComponent} from './marc-edit.component';
import {BrowseAuthorityComponent} from './browse.component';
import {ManageAuthorityComponent} from './manage.component';
import {AuthorityMergeDialogComponent} from './merge-dialog.component';
import {BrowseService} from './browse.service';
import {BibListModule} from '@eg/staff/share/bib-list/bib-list.module';

@NgModule({
  declarations: [
    AuthorityMarcEditComponent,
    BrowseAuthorityComponent,
    ManageAuthorityComponent,
    AuthorityMergeDialogComponent
  ],
  imports: [
    StaffCommonModule,
    CommonWidgetsModule,
    MarcEditModule,
    AuthorityRoutingModule,
    BibListModule
  ],
  providers: [
    BrowseService
  ]
})

export class AuthorityModule {
}
