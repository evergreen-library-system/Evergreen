import {Pager} from '@eg/share/util/pager';
import { Component, Input, OnInit, inject } from '@angular/core';
import {Router} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {AdminPageComponent} from '../../../share/admin-page/admin-page.component';
import { StaffCommonModule } from '@eg/staff/common.module';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';

@Component({
    templateUrl: './search-filter-group.component.html',
    imports: [StaffCommonModule, FmRecordEditorComponent]
})

export class SearchFilterGroupComponent extends AdminPageComponent implements OnInit {
    private router = inject(Router);

    @Input() gridDataSource: GridDataSource;

    ngOnInit() {
        this.gridDataSource = new GridDataSource();
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: {}
            };
            return this.pcrud.retrieveAll('asfg', searchOps);
        };
        this.grid().onRowActivate.subscribe(
            (idlThing: IdlObject) => {
                const idToEdit = idlThing.id();
                this.navigateToEditPage(idToEdit);
            }
        );
    }

    createNew = () => {
        this.editDialog().mode = 'create';
        this.editDialog().recordId = null;
        this.editDialog().record = null;
        this.editDialog().hiddenFieldsList = ['id', 'create_date'];
        this.editDialog().open({size: 'lg'}).subscribe(
            { next: ok => {
                this.createString().current()
                    .then(str => this.toast.success(str));
                this.grid().reload();
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.createErrString().current()
                        .then(str => this.toast.danger(str));
                }
            } }
        );
    };

    editSelected = (sfGroups: IdlObject[]) => {
        const idToEdit = sfGroups[0].id();
        this.navigateToEditPage(idToEdit);
    };

    navigateToEditPage(id: any) {
        this.router.navigate(['/staff/admin/local/actor/search_filter_group/' + id]);
    }

}
