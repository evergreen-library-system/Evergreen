import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from, empty, range} from 'rxjs';
import {concatMap, tap, takeLast} from 'rxjs/operators';
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
        private patronService: PatronService,
        private context: PatronContextService
    ) {}

    ngOnInit() {

        this.dataSource.getRows = (pager: Pager, sort: any[]) =>
            from(this.patrons.slice(pager.offset, pager.offset + pager.limit));

        if (this.context.patron) {
            this.getGroupUsers(this.context.patron.usrgroup());

        } else {
            this.patronService.getById(this.patronId)
            .then(patron => this.getGroupUsers(patron.usrgroup()));
        }
    }

    getGroupUsers(usergroup: number) {
        this.usergroup = usergroup;
        this.patrons = [];

        this.pcrud.search('au',
            {usrgroup: usergroup, deleted: 'f'}, {authoritative: true})
        .pipe(concatMap(u => {

            const promise = this.context.getPatronVitalStats(u.id())
            .then(stats => {
                this.totalOwed += stats.fines.balance_owed;
                this.totalOut += stats.checkouts.total_out;
                this.totalOverdue += stats.checkouts.overdue;
                u._stats = stats;
                this.patrons.push(u);
            });

            return from(promise);

        })).subscribe(null, null, () => this.groupGrid.reload());
    }

    movePatronToGroup() {

        this.moveToGroupDialog.open().subscribe(barcode => {
            if (!barcode) { return null; }

            this.patronService.getByBarcode(barcode)
            .then(resp => {
                if (resp === null) {
                    this.userNotFoundDialog.open();
                    return null;
                }

                resp.usrgroup(this.usergroup);
                resp.ischanged(true);

                return this.net.request(
                    'open-ils.actor',
                    'open-ils.actor.patron.update',
                    this.auth.token(), resp
                ).toPromise();
            })
            .then(resp => {
                if (resp === null) { return null; }

                const evt = this.evt.parse(resp);
                if (evt) {
                    console.error(evt);
                    alert(evt);
                    return null;
                }

                return this.getGroupUsers(this.usergroup);
            })
            .then(resp => {
                if (resp === null) { return null; }
                this.groupGrid.reload();
            });
        });
    }
}
