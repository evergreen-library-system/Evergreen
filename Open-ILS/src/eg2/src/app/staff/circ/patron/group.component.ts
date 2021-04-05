import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {of, from, empty, range} from 'rxjs';
import {concatMap, map, tap, takeLast} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService, PcrudContext} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
  templateUrl: 'group.component.html',
  selector: 'eg-patron-group'
})
export class PatronGroupComponent implements OnInit {

    @Input() patronId: number;
    patrons: IdlObject[] = [];
    totalOwed = 0;
    totalOut = 0;
    totalOverdue = 0;
    usergroup: number;

    cellTextGenerator: GridCellTextGenerator;
    dataSource: GridDataSource = new GridDataSource();
    @ViewChild('groupGrid') private groupGrid: GridComponent;
    @ViewChild('moveToGroupDialog') private moveToGroupDialog: PromptDialogComponent;
    @ViewChild('userNotFoundDialog') private userNotFoundDialog: AlertDialogComponent;

    constructor(
        private router: Router,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private org: OrgService,
        private pcrud: PcrudService,
        private ngLocation: Location,
        private patronService: PatronService,
        private context: PatronContextService
    ) {}

    ngOnInit() {

        this.cellTextGenerator = {
            barcode: row => row.card().barcode()
        };

        this.dataSource.getRows = (pager: Pager, sort: any[]) =>
            from(this.patrons.slice(pager.offset, pager.offset + pager.limit));

        if (this.context.patron) {
            this.getGroupUsers(this.context.patron.usrgroup());

        } else {
            this.patronService.getById(this.patronId)
            .then(patron => this.getGroupUsers(patron.usrgroup()));
        }
    }

    getGroupUsers(usergroup: number): Promise<any> {
        this.usergroup = usergroup;
        this.patrons = [];

        return this.pcrud.search('au',
            {usrgroup: usergroup, deleted: 'f'},
            {flesh: 1, flesh_fields: {au: ['card']}},
            {authoritative: true})
        .pipe(concatMap(u => {

            const promise = this.patronService.getVitalStats(u.id())
            .then(stats => {
                this.totalOwed += stats.fines.balance_owed;
                this.totalOut += stats.checkouts.total_out;
                this.totalOverdue += stats.checkouts.overdue;
                u._stats = stats;
                this.patrons.push(u);
            });

            return from(promise);

        })).toPromise().then(_ => this.groupGrid.reload());
    }

    // If rows are present, we are moving selected rows to a different group
    // Otherwise, we are moving another user into this group.
    movePatronToGroup(rows?: IdlObject[]) {

        this.moveToGroupDialog.promptValue = '';

        this.moveToGroupDialog.open().subscribe(barcode => {
            if (!barcode) { return null; }

            this.patronService.getByBarcode(barcode)
            .then(resp => {
                if (resp === null) {
                    this.userNotFoundDialog.open();
                    return null;
                }

                let users: IdlObject[] = [resp];
                let usergroup: number = this.usergroup;
                if (rows) {
                    users = rows;
                    usergroup = resp.usrgroup();
                }

                let allOk = true;
                from(users).pipe(concatMap(user => {

                    user.usrgroup(usergroup);
                    user.ischanged(true);

                    return this.net.request(
                        'open-ils.actor',
                        'open-ils.actor.patron.update',
                        this.auth.token(), user
                    );
                })).subscribe(
                    resp2 => { if (this.evt.parse(resp2)) { allOk = false; } },
                    err => console.error(err),
                    () => { if (allOk) { this.refresh(); } }
                );
            });
        });
    }

    refresh() {
        this.context.refreshPatron()
        .then(_ => this.usergroup = this.context.patron.usrgroup())
        .then(_ => this.getGroupUsers(this.usergroup))
        .then(_ => this.groupGrid.reload());
    }

    removeSelected(rows: IdlObject[]) {

        from(rows.map(r => r.id())).pipe(concatMap(id => {
            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.usergroup.new',
                this.auth.token(), id, true
            );
        }))
        .subscribe(null, null, () => this.refresh());
    }

    onRowActivate(row: IdlObject) {
        const url = this.ngLocation.prepareExternalUrl(
            `/staff/circ/patron/${row.id()}/checkout`);
        window.open(url);
    }

    cloneSelected(rows: IdlObject[]) {
        if (rows.length) {
            const url = this.ngLocation.prepareExternalUrl(
                `/staff/circ/patron/register/clone/${rows[0].id()}`);
            window.open(url);
        }
    }
}
