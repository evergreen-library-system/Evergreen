import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {Observable, of} from 'rxjs';
import {map, tap, switchMap, catchError} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {StringService} from '@eg/share/string/string.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';

@Component({
    templateUrl: './account.component.html'
})
export class SipAccountComponent implements OnInit {

    accountId: number;
    account: IdlObject;
    usrCboxSource: (term: string) => Observable<ComboboxEntry>;
    usrCboxEntries: ComboboxEntry[];
    settingGroups: ComboboxEntry[];
    usrId: number;
    settingsSource: GridDataSource = new GridDataSource();
    deleteGroupAccounts: IdlObject[] = [];
    accountPreSave: (mode: string, account: IdlObject) => void;
    createMode = false;

    @ViewChild('cloneDialog') cloneDialog: FmRecordEditorComponent;
    @ViewChild('settingDialog') settingDialog: FmRecordEditorComponent;
    @ViewChild('settingGrid') settingGrid: GridComponent;
    @ViewChild('deleteGroupDialog') deleteGroupDialog: DialogComponent;
    @ViewChild('passwordDialog') passwordDialog: PromptDialogComponent;

    constructor(
        private route: ActivatedRoute,
        private router: Router,
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private evt: EventService,
        private pcrud: PcrudService
    ) {}

    ngOnInit() {

        this.route.paramMap.subscribe(params => {
            if (params.get('id') === 'new') {
                this.account = this.idl.create('sipacc'); // dummy
                this.createMode = true;
                return;
            }

            this.accountId = Number(params.get('id'));
            this.loadAccount().toPromise(); // force it to run
        });

        this.fetchGroups();

        this.usrCboxSource = term => {

            const filter: any = {deleted: 'f', active: 't'};

            if (this.account && this.account.usr()) {
                filter['-or'] = [
                    {id: this.account.usr().id()},
                    {usrname: {'ilike': `%${term}%`}}
                ];
            } else {
                filter.usrname = {'ilike': `%${term}%`};
            }

            return this.pcrud.search('au', filter, {
                order_by: {au: 'usrname'},
                limit: 50 // Avoid huge lists
            }
            ).pipe(map(user => {
                return {id: user.id(), label: user.usrname()};
            }));
        };

        this.settingsSource.getRows = (pager: Pager, sort: any[]) => {
            if (!this.account && this.account.setting_group()) {
                return of();
            }

            const orderBy: any = {sipset: 'name'};
            if (sort.length) {
                orderBy.sipset = sort[0].name + ' ' + sort[0].dir;
            }

            return this.pcrud.search('sipset',
                {setting_group: this.account.setting_group().id()},
                {order_by: orderBy},
            );
        };

        this.accountPreSave = (mode: string, account: IdlObject) => {
            // Migrate data collected from custom templates into
            // the object to be saved.
            account.setting_group(this.account.setting_group().id());
            account.usr(this.account.usr().id());
            account.sip_username(this.account.sip_username());
            account.sip_password(this.account.sip_password());
        };
    }

    fetchGroups() {
        this.pcrud.retrieveAll('sipsetg',
            {order_by: {sipsetg: 'label'}}, {atomic: true})
        .subscribe(grps => {
            this.settingGroups =
                grps.map(g => ({id: g.id(), label: g.label()}));
        });
    }

    loadAccount(): Observable<any> {
        return this.pcrud.retrieve('sipacc', this.accountId, {
            flesh: 2,
            flesh_fields: {
                sipacc: ['usr', 'setting_group', 'workstation'],
                sipsetg: ['settings']
            }}, {authoritative: true}
        ).pipe(tap(acc => {
            this.account = acc;
            this.usrId = acc.usr().id();
            this.usrCboxEntries =
                [{id: acc.usr().id(), label: acc.usr().usrname()}];
        }));
    }

    grpChanged(entry: ComboboxEntry) {

        if (!entry) {
            this.account.setting_group(null);
            return;
        }

        this.pcrud.retrieve('sipsetg', entry.id,
            {flesh: 1, flesh_fields: {sipsetg: ['settings']}})
        .subscribe(grp => {
            this.account.setting_group(grp);
            if (this.settingGrid) {
                this.settingGrid.reload();
            }
        });
    }

    usrChanged(entry: ComboboxEntry) {
        if (!entry) {
            this.account.usr(null);
            return;
        }

        this.pcrud.retrieve('au', entry.id)
            .subscribe(usr => this.account.usr(usr));
    }


    // Create a new setting group
    // Clone the settings for the currently selected group into the new group
    // Point our account at the new group.
    openCloneDialog() {
        this.cloneDialog.open().subscribe(resp => {
            if (!resp) { return; }

            this.settingGroups.unshift({id: resp.id(), label: resp.label()});

            const settings = this.account.setting_group().settings()
                .map(setting => {
                    const clone = this.idl.clone(setting);
                    clone.setting_group(resp.id());
                    clone.isnew(true);
                    clone.id(null);
                    return clone;
                });

            // avoid de-fleshing the group on the active account
            const modified = this.idl.clone(this.account);
            modified.setting_group(resp.id());
            modified.ischanged(true);

            this.pcrud.autoApply(settings.concat(modified)).toPromise()
            .then(_ => this.refreshAccount());
        });
    }

    openDeleteDialog() {
        this.deleteGroupDialog.open().subscribe(
            ok => {
                if (ok) {
                    this.refreshAccount();
                }
            }
        );
    }

    accountSaved(account) {

        if (this.createMode) {
            account.isnew(true);
        } else {
            account.ischanged(true);
        }

        this.net.request('open-ils.sip2',
            'open-ils.sip2.account.cud', this.auth.token(), account)
        .subscribe(acc => {

            const evt = this.evt.parse(acc);

            if (evt) {
                console.error(evt);
                return;
            }

            if (this.createMode) {
                this.router.navigate(
                    [`/staff/admin/server/sip/account/${acc.id()}`]);
            } else {
                this.refreshAccount();
            }
        });
    }

    editFirstSetting(rows: any) {
        if (rows.length > 0) {
            this.editSetting(rows[0]);
        }
    }

    refreshAccount() {
        this.loadAccount().subscribe(_ => {
            setTimeout(() => {
                if (this.settingGrid) {
                    this.settingGrid.reload();
                }
            });
        });
    }

    editSetting(row: any) {
        // Default Settings group is read-only
        if (row.setting_group() === 1) { return; }

        this.settingDialog.record = this.idl.clone(row);
        this.settingDialog.open().subscribe(
            ok => this.refreshAccount(),
            err => {} // todo toast
        );
    }


    setPassword() {
        this.passwordDialog.open().subscribe(value => {
            // API will translate this into an actor.passwd
            this.account.sip_password(value);
        });
    }
}

