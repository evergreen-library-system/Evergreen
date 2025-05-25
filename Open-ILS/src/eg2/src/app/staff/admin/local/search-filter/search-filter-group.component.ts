import {Pager} from '@eg/share/util/pager';
import {Location} from '@angular/common';
import {FormatService} from '@eg/core/format.service';
import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {AdminPageComponent} from '../../../share/admin-page/admin-page.component';

@Component({
    templateUrl: './search-filter-group.component.html'
})

export class SearchFilterGroupComponent extends AdminPageComponent implements OnInit {

    @Input() gridDataSource: GridDataSource;
    @ViewChild('grid', {static: true}) grid: GridComponent;
    @ViewChild('createString') createString: StringComponent;
    @ViewChild('createErrString') createErrString: StringComponent;
    @ViewChild('deleteFailedString') deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString') deleteSuccessString: StringComponent;

    constructor(
        route: ActivatedRoute,
        ngLocation: Location,
        format: FormatService,
        idl: IdlService,
        org: OrgService,
        auth: AuthService,
        pcrud: PcrudService,
        perm: PermService,
        toast: ToastService,
        private router: Router,
        broadcaster: BroadcastService
    ) {
        super(route, ngLocation, format, idl, org, auth, pcrud, perm, toast, broadcaster);
    }

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
        this.grid.onRowActivate.subscribe(
            (idlThing: IdlObject) => {
                const idToEdit = idlThing.id();
                this.navigateToEditPage(idToEdit);
            }
        );
    }

    createNew = () => {
        this.editDialog.mode = 'create';
        this.editDialog.recordId = null;
        this.editDialog.record = null;
        this.editDialog.hiddenFieldsList = ['id', 'create_date'];
        this.editDialog.open({size: 'lg'}).subscribe(
            { next: ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
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
