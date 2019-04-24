import {Component, AfterViewInit, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridColumn} from '@eg/share/grid/grid';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';

@Component({
  templateUrl: 'match-set-list.component.html'
})
export class MatchSetListComponent implements AfterViewInit {

    contextOrg: IdlObject;
    gridSource: GridDataSource;
    deleteSelected: (rows: IdlObject[]) => void;
    createNew: () => void;
    @ViewChild('grid') grid: GridComponent;
    @ViewChild('editDialog') editDialog: FmRecordEditorComponent;

    constructor(
        private router: Router,
        private pcrud: PcrudService,
        private auth: AuthService,
        private org: OrgService) {

        this.gridSource = new GridDataSource();
        this.contextOrg = this.org.get(this.auth.user().ws_ou());

        this.gridSource.getRows = (pager: Pager) => {
            const orgs = this.org.ancestors(this.contextOrg, true);
            return this.pcrud.search('vms', {owner: orgs}, {
                order_by: {vms: ['name']},
                limit: pager.limit,
                offset: pager.offset
            });
        };

        this.createNew = () => {
            this.editDialog.mode = 'create';
            this.editDialog.open({size: 'lg'}).then(
                ok => this.grid.reload(),
                err => {}
            );
        };

        this.deleteSelected = (matchSets: IdlObject[]) => {
            matchSets.forEach(matchSet => matchSet.isdeleted(true));
            this.pcrud.autoApply(matchSets).subscribe(
                val => console.debug('deleted: ' + val),
                err => {},
                ()  => this.grid.reload()
            );
        };
    }

    ngAfterViewInit() {
        this.grid.onRowActivate.subscribe(
            (matchSet: IdlObject) => {
                this.editDialog.mode = 'update';
                this.editDialog.recId = matchSet.id();
                this.editDialog.open({size: 'lg'}).then(
                    ok => this.grid.reload(),
                    err => {}
                );
            }
        );
    }

    orgOnChange(org: IdlObject) {
        this.contextOrg = org;
        this.grid.reload();
    }
}

