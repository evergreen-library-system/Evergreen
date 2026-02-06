import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {AuthorityRoutingModule} from './routing.module';
import {AuthorityMarcEditComponent} from './marc-edit.component';
import {BrowseAuthorityComponent} from './browse.component';
import {ManageAuthorityComponent} from './manage.component';
import {AuthorityMergeDialogComponent} from './merge-dialog.component';
import {BrowseService} from './browse.service';
import {BibListModule} from '@eg/staff/share/bib-list/bib-list.module';

@NgModule({
    imports: [
        AuthorityMarcEditComponent,
        BrowseAuthorityComponent,
        ManageAuthorityComponent,
        AuthorityMergeDialogComponent,
        StaffCommonModule,
        CommonWidgetsModule,
        AuthorityRoutingModule,
        BibListModule
    ],
    providers: [
        BrowseService
    ]
})

export class AuthorityModule {
}
