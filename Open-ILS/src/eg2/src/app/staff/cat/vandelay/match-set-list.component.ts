import {Component, AfterViewInit, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';

@Component({
    templateUrl: 'match-set-list.component.html'
})
export class MatchSetListComponent implements AfterViewInit {

    contextOrg: IdlObject;
    gridSource: GridDataSource;
    deleteSelected: (rows: IdlObject[]) => void;
    createNew: () => void;
    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;

    cellTextGenerator: GridCellTextGenerator;

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

        this.cellTextGenerator = {
            name: row => row.name()
        };

        this.createNew = () => {
            this.editDialog.mode = 'create';
            this.editDialog.open({size: 'lg'})
                .subscribe(() => this.grid.reload());
        };

        this.deleteSelected = (matchSets: IdlObject[]) => {
            matchSets.forEach(matchSet => matchSet.isdeleted(true));
            this.pcrud.autoApply(matchSets).subscribe(
                val => console.debug('deleted: ' + val),
                (err: unknown) => {},
                ()  => this.grid.reload()
            );
        };
    }

    ngAfterViewInit() {
        this.grid.onRowActivate.subscribe(
            (matchSet: IdlObject) => {
                this.editDialog.mode = 'update';
                this.editDialog.recordId = matchSet.id();
                this.editDialog.open({size: 'lg'})
                    // eslint-disable-next-line rxjs/no-nested-subscribe
                    .subscribe(() => this.grid.reload());
            }
        );
        this.editDialog.fieldOptions =
            {mtype:{customValues:[
                {id:'biblio', label:$localize`Bibliographic Records`},
                {id:'serial', label:$localize`Serial Records`},
                {id:'authority', label:$localize`Authority Records`}
            ]}};
    }

    orgOnChange(org: IdlObject) {
        this.contextOrg = org;
        this.grid.reload();
    }
}

