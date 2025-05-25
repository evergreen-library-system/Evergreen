import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {EMPTY, Observable, Observer} from 'rxjs';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {LocaleService} from '@eg/core/locale.service';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';

import {EditOuSettingDialogComponent
} from '@eg/staff/admin/local/org-unit-settings/edit-org-unit-setting-dialog.component';
import {OuSettingHistoryDialogComponent
} from '@eg/staff/admin/local/org-unit-settings/org-unit-setting-history-dialog.component';
import {OuSettingJsonDialogComponent
} from '@eg/staff/admin/local/org-unit-settings/org-unit-setting-json-dialog.component';

export class OrgUnitSetting {
    name: string;
    label: string;
    grp: string;
    description: string;
    value: any;
    value_str: any;
    dataType: string;
    fmClass: string;
    _idlOptions: IdlObject[];
    _org_unit: IdlObject;
    context: string;
    view_perm: string;
    _history: any[];
}

@Component({
    templateUrl: './org-unit-settings.component.html'
})

export class OrgUnitSettingsComponent implements OnInit {

    contextOrg: IdlObject;

    initDone = false;
    midFetch = false;
    gridDataSource: GridDataSource;
    gridTemplateContext: any;
    prevFilter: string;
    currentHistory: any[];
    currentOptions: any[];
    jsonFieldData: {};
    @ViewChild('orgUnitSettingsGrid', { static: true }) orgUnitSettingsGrid: GridComponent;

    @ViewChild('editOuSettingDialog', { static: true })
    private editOuSettingDialog: EditOuSettingDialogComponent;
    @ViewChild('orgUnitSettingHistoryDialog', { static: true })
    private orgUnitSettingHistoryDialog: OuSettingHistoryDialogComponent;
    @ViewChild('ouSettingJsonDialog', { static: true })
    private ouSettingJsonDialog: OuSettingJsonDialogComponent;

    @ViewChild('progress') private progress: ProgressDialogComponent;

    refreshSettings: boolean;
    renderFromPrefs: boolean;

    settingTypeArr: any[];

    @Input() filterString: string;

    constructor(
        private org: OrgService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private toast: ToastService,
        private locale: LocaleService,
        private net: NetService,
        private idl: IdlService
    ) {
        this.gridDataSource = new GridDataSource();
        this.refreshSettings = true;
        this.renderFromPrefs = true;

        this.contextOrg = this.org.get(this.auth.user().ws_ou());
    }

    ngOnInit() {
        this.initDone = true;
        this.settingTypeArr = [];
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.fetchSettingTypes(pager);
        };
        this.orgUnitSettingsGrid.onRowActivate.subscribe((setting: OrgUnitSetting) => {
            this.showEditSettingValueDialog(setting);
        });
    }

    fetchSettingTypes(pager: Pager): Observable<any> {
        if (this.midFetch) { return EMPTY; }
        this.midFetch = true;
        return new Observable<any>(observer => {
            this.pcrud.retrieveAll('coust', {flesh: 1, flesh_fields: {
                'coust': ['grp', 'view_perm']
            }},
            { authoritative: true }).subscribe(
                { next: settingTypes => this.allocateSettingTypes(settingTypes), error: (err: unknown) => {}, complete: ()  => {
                    this.refreshSettings = false;
                    this.mergeSettingValues().then(
                        ok => {
                            this.flattenSettings(observer);
                            this.filterCoust();
                            this.midFetch = false;
                        }
                    );
                } }
            );
        });
    }

    mergeSettingValues(): Promise<any> {
        const settingNames = this.settingTypeArr.map(setting => setting.name);
        const orgs = this.org.ancestors(this.contextOrg.id());
        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.ou_setting.ancestor_default.batch',
                this.contextOrg.id(), settingNames, this.auth.token()
            ).subscribe(
                { next: blob => {
                    const settingVals = Object.keys(blob).map(key => {
                        return {'name': key, 'setting': blob[key]};
                    });
                    settingVals.forEach(key => {
                        if (key.setting) {
                            if (orgs.indexOf(this.org.get(key.setting.org)) || this.contextOrg.id() === key.setting.org) {
                                const settingsObj = this.settingTypeArr.filter(
                                    setting => setting.name === key.name
                                )[0];
                                if (settingsObj) {
                                    settingsObj.value_str = key.setting.value;
                                    settingsObj.value = this.parseValType(key.setting.value, settingsObj.dataType);
                                    if (settingsObj.dataType === 'link' && (key.setting.value || key.setting.value === 0)) {
                                        this.fetchLinkedField(settingsObj.fmClass, key.setting.value, settingsObj.value_str).then(res => {
                                            settingsObj.value_str = res;
                                        });
                                    }
                                    settingsObj._org_unit = this.org.get(key.setting.org);
                                    settingsObj.context = settingsObj._org_unit.shortname();
                                }
                            } else {
                                key.setting = null;
                            }
                        }
                    });
                    resolve(this.settingTypeArr);
                }, error: (err: unknown) => reject(err) }
            );
        });
    }

    fetchLinkedField(fmClass, id, val) {
        return new Promise((resolve, reject) => {
            return this.pcrud.retrieve(fmClass, id).subscribe(linkedField => {
                const fname = this.idl.getClassSelector(fmClass) || this.idl.classes[fmClass].pkey || 'id';
                val = this.idl.toHash(linkedField)[fname];
                resolve(val);
            });
        });
    }

    fetchHistory(setting): Promise<any> {
        const name = setting.name;
        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.org_unit.settings.history.retrieve',
                this.auth.token(), name, this.contextOrg.id()
            ).subscribe({ next: res => {
                this.currentHistory = [];
                if (!Array.isArray(res)) {
                    res = [res];
                }
                res.forEach(log => {
                    log.org = this.org.get(log.org);
                    log.new_value_str = log.new_value;
                    log.original_value_str = log.original_value;
                    if (setting.dataType === 'link') {
                        if (log.new_value) {
                            this.fetchLinkedField(setting.fmClass, Number(log.new_value), log.new_value_str).then(val => {
                                log.new_value_str = val;
                            });
                        }
                        if (log.original_value) {
                            this.fetchLinkedField(setting.fmClass, Number(log.original_value), log.original_value_str).then(val => {
                                log.original_value_str = val;
                            });
                        }
                    }
                    if (log.new_value_str) { log.new_value_str = log.new_value_str.replace(/^"(.*)"$/, '$1'); }
                    if (log.original_value_str) { log.original_value_str = log.original_value_str.replace(/^"(.*)"$/, '$1'); }
                });
                this.currentHistory = res;
                this.currentHistory.sort((a, b) => {
                    return a.date_applied < b.date_applied ? 1 : -1;
                });

                resolve(this.currentHistory);
            }, error: (err: unknown) => {reject(err); } });
        });
    }

    allocateSettingTypes(coust: IdlObject) {
        const entry = new OrgUnitSetting();
        entry.name = coust.name();
        entry.label = coust.label();
        entry.dataType = coust.datatype();
        if (coust.fm_class()) { entry.fmClass = coust.fm_class(); }
        if (coust.description()) { entry.description = coust.description(); }
        // For some reason some setting types don't have a grp, should look into this...
        if (coust.grp()) { entry.grp = coust.grp().label(); }
        if (coust.view_perm()) {
            entry.view_perm = coust.view_perm().code();
        }

        this.settingTypeArr.push(entry);
    }

    flattenSettings(observer: Observer<any>) {
        const sorted = this.settingTypeArr.sort((a,b) => {
            if (a.grp && b.grp) {
                if (a.grp.toLowerCase() < b.grp.toLowerCase()) {
                    return -1;
                } else if (a.grp.toLowerCase() > b.grp.toLowerCase()) {
                    return 1;
                }
            } else if (a.grp) {
                return -1;
            } else if (b.grp) {
                return 1;
            }

            if (a.label.toLowerCase() < b.label.toLowerCase()) {
                return -1;
            } else if (a.label.toLowerCase() > b.label.toLowerCase()) {
                return 1;
            }

            return 0;
        });
        this.gridDataSource.data = sorted;
        observer.complete();
    }

    contextOrgChanged(org: IdlObject) {
        this.updateGrid(org);
    }

    applyFilter(clear?: boolean) {
        if (clear) { this.filterString = ''; }
        this.orgUnitSettingsGrid.context.pager.toFirst();
        this.updateGrid(this.contextOrg);
    }

    updateSetting(obj, entry, noToast?: boolean): Promise<any> {
        Object.keys(obj.setting).forEach(
            key => obj.setting[key] = this.parseValType(obj.setting[key], entry.dataType)
        );
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.org_unit.settings.update',
            this.auth.token(), obj.context.id(), obj.setting
        ).toPromise().then(res => {
            if (!noToast) {
                this.toast.success(entry.label + ' Updated.');
                if (obj.context.id() !== this.contextOrg.id()) {
                    this.toast.warning(
                        'The setting you edited is not the currently chosen org unit, therefore the changes you made are not visible.'
                    );
                }
            }

            if (!obj.setting[entry.name]) {
                const settingsObj = this.settingTypeArr.filter(
                    setting => setting.name === entry.name
                )[0];
                settingsObj.value = null;
                settingsObj.value_str = null;
                settingsObj._org_unit = null;
                settingsObj.context = null;
            }
            this.mergeSettingValues();
        },
        err => {
            this.toast.danger(entry.label + ' failed to update: ' + err.desc);
        });
    }

    showEditSettingValueDialog(entry: OrgUnitSetting) {
        this.editOuSettingDialog.entry = entry;
        this.editOuSettingDialog.entryValue = entry.value;
        this.editOuSettingDialog.entryContext = entry._org_unit || this.contextOrg;
        this.editOuSettingDialog.open({size: 'lg'}).subscribe(
            res => {
                this.updateSetting(res, entry);
            }
        );
    }

    showHistoryDialog(entry: OrgUnitSetting) {
        if (entry) {
            this.fetchHistory(entry).then(
                fetched => {
                    this.orgUnitSettingHistoryDialog.history = this.currentHistory;
                    this.orgUnitSettingHistoryDialog.gridDataSource.data = this.currentHistory;
                    this.orgUnitSettingHistoryDialog.entry = entry;
                    this.orgUnitSettingHistoryDialog.open({size: 'lg'}).subscribe(res => {
                        if (res.revert) {
                            this.updateSetting(res, entry);
                        }
                    });
                }
            );
        }
    }

    showJsonDialog(isExport: boolean) {
        this.ouSettingJsonDialog.isExport = isExport;
        this.ouSettingJsonDialog.jsonData = '';

        if (isExport) {
            const jsonObj: any = {};
            this.gridDataSource.data.forEach(entry => {
                jsonObj[entry.name] = {
                    org: this.contextOrg.id(),
                    value: entry.value === undefined ? null : entry.value
                };
            });

            this.ouSettingJsonDialog.jsonData = JSON.stringify(jsonObj);
        }

        this.ouSettingJsonDialog.open({size: 'lg'}).subscribe(res => {
            if (res.apply && res.jsonData) {
                const jsonSettings = JSON.parse(res.jsonData);

                this.progress.update({
                    max: Object.entries(jsonSettings).length,
                    value: 1
                });

                this.progress.open();

                let promise = Promise.resolve();
                Object.entries(jsonSettings).forEach((fields) => {
                    const entry = this.settingTypeArr.find(x => x.name === fields[0]);
                    const obj = {setting: {}, context: {}};
                    const val = this.parseValType(fields[1]['value'], entry.dataType);
                    obj.setting[fields[0]] = val;
                    obj.context = this.org.get(fields[1]['org']);
                    promise = promise
                        .then(_ => this.updateSetting(obj, entry, true))
                        .then(_ => this.progress.increment());
                });

                promise.finally(() => this.progress.close());
            }
        });
    }

    parseValType(value, dataType) {
        if (value === null || value === undefined) {return null;}

        const intTypes = ['integer', 'currency', 'float'];
        if (intTypes.includes(dataType)) {
            value = Number(value);
        }

        if (typeof value === 'string') {
            value = value.replace(/^"(.*)"$/, '$1');
        }

        if (typeof value === 'string' && dataType === 'bool') {
            if (value.match(/^t/)) {
                value = true;
            } else {
                value = false;
            }
        }

        return value;
    }

    filterCoust() {
        this.prevFilter = this.filterString;
        if (this.filterString) {
            this.gridDataSource.data = [];
            const tempGrid = this.settingTypeArr;
            tempGrid.forEach(row => {
                const containsString =
                     row.name.toLocaleLowerCase(this.locale.currentLocaleCode())
                         .includes(this.filterString.toLocaleLowerCase(this.locale.currentLocaleCode())) ||
                     row.label.toLocaleLowerCase(this.locale.currentLocaleCode())
                         .includes(this.filterString.toLocaleLowerCase(this.locale.currentLocaleCode())) ||
                     (row.grp && row.grp.toLocaleLowerCase(this.locale.currentLocaleCode())
                         .includes(this.filterString.toLocaleLowerCase(this.locale.currentLocaleCode()))) ||
                     (row.description && row.description.toLocaleLowerCase(this.locale.currentLocaleCode())
                         .includes(this.filterString.toLocaleLowerCase(this.locale.currentLocaleCode())));
                if (containsString) {
                    this.gridDataSource.data.push(row);
                }
            });
        } else {
            this.gridDataSource.data = this.settingTypeArr;
        }
    }

    updateGrid(org) {
        if (this.contextOrg !== org) {
            this.contextOrg = org;
            this.refreshSettings = true;
        }

        if (this.filterString !== this.prevFilter) {
            this.mergeSettingValues().then(
                res => this.filterCoust()
            );
            this.refreshSettings = true;
        }

        if (this.refreshSettings) {
            this.settingTypeArr = [];
            this.orgUnitSettingsGrid.reloadWithoutPagerReset();
        }
    }
}
