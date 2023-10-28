/* eslint-disable no-case-declarations, no-cond-assign, no-magic-numbers, no-self-assign, no-shadow */
import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {empty, from} from 'rxjs';
import {concatMap, tap} from 'rxjs/operators';
import {OrgService} from '@eg/core/org.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {DateUtil} from '@eg/share/util/date';
import {ProfileSelectComponent} from '@eg/staff/share/patron/profile-select.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringService} from '@eg/share/string/string.service';
import {EventService} from '@eg/core/event.service';
import {PermService} from '@eg/core/perm.service';
import {SecondaryGroupsDialogComponent} from './secondary-groups.component';
import {ServerStoreService} from '@eg/core/server-store.service';
import {EditToolbarComponent, VisibilityLevel} from './edit-toolbar.component';
import {PatronSearchFieldSet} from '@eg/staff/share/patron/search.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {HoldNotifyUpdateDialogComponent} from './hold-notify-update.component';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {PrintService} from '@eg/share/print/print.service';
import {WorkLogService} from '@eg/staff/share/worklog/worklog.service';

const PATRON_FLESH_FIELDS = [
    'cards',
    'card',
    'groups',
    'standing_penalties',
    'settings',
    'addresses',
    'billing_address',
    'mailing_address',
    'stat_cat_entries',
    'waiver_entries',
    'usr_activity',
    'notes'
];

const COMMON_USER_SETTING_TYPES = [
    'circ.holds_behind_desk',
    'circ.autorenew.opt_in',
    'circ.collections.exempt',
    'opac.hold_notify',
    'opac.default_phone',
    'opac.default_pickup_location',
    'opac.default_sms_carrier',
    'opac.default_sms_notify'
];

const PERMS_NEEDED = [
    'EDIT_SELF_IN_CLIENT',
    'UPDATE_USER',
    'CREATE_USER',
    'CREATE_USER_GROUP_LINK',
    'UPDATE_PATRON_COLLECTIONS_EXEMPT',
    'UPDATE_PATRON_CLAIM_RETURN_COUNT',
    'UPDATE_PATRON_CLAIM_NEVER_CHECKED_OUT_COUNT',
    'UPDATE_PATRON_ACTIVE_CARD',
    'UPDATE_PATRON_PRIMARY_CARD'
];

enum FieldVisibility {
    REQUIRED = 3,
    VISIBLE = 2,
    SUGGESTED = 1
}

// 3 == value universally required
// 2 == field is visible by default
// 1 == field is suggested by default
const DEFAULT_FIELD_VISIBILITY = {
    'ac.barcode': FieldVisibility.REQUIRED,
    'au.usrname': FieldVisibility.REQUIRED,
    'au.passwd': FieldVisibility.REQUIRED,
    'au.first_given_name': FieldVisibility.REQUIRED,
    'au.family_name': FieldVisibility.REQUIRED,
    'au.pref_first_given_name': FieldVisibility.VISIBLE,
    'au.pref_family_name': FieldVisibility.VISIBLE,
    'au.ident_type': FieldVisibility.REQUIRED,
    'au.ident_type2': FieldVisibility.VISIBLE,
    'au.home_ou': FieldVisibility.REQUIRED,
    'au.profile': FieldVisibility.REQUIRED,
    'au.expire_date': FieldVisibility.REQUIRED,
    'au.net_access_level': FieldVisibility.REQUIRED,
    'aua.address_type': FieldVisibility.REQUIRED,
    'aua.post_code': FieldVisibility.REQUIRED,
    'aua.street1': FieldVisibility.REQUIRED,
    'aua.street2': FieldVisibility.VISIBLE,
    'aua.city': FieldVisibility.REQUIRED,
    'aua.county': FieldVisibility.VISIBLE,
    'aua.state': FieldVisibility.VISIBLE,
    'aua.country': FieldVisibility.REQUIRED,
    'aua.valid': FieldVisibility.VISIBLE,
    'aua.within_city_limits': FieldVisibility.VISIBLE,
    'stat_cats': FieldVisibility.SUGGESTED,
    'surveys': FieldVisibility.SUGGESTED,
    'au.name_keywords': FieldVisibility.SUGGESTED
};

interface StatCat {
    cat: IdlObject;
    entries: ComboboxEntry[];
}

@Component({
    templateUrl: 'edit.component.html',
    selector: 'eg-patron-edit',
    styleUrls: ['edit.component.css']
})
export class EditComponent implements OnInit {

    @Input() patronId: number = null;
    @Input() cloneId: number = null;
    @Input() stageUsername: string = null;

    _toolbar: EditToolbarComponent;
    @Input() set toolbar(tb: EditToolbarComponent) {
        if (tb !== this._toolbar) {
            this._toolbar = tb;

            // Our toolbar component may not be available during init,
            // since it pops in and out of existence depending on which
            // patron tab is open.  Wait until we know it's defined.
            if (tb) {
                tb.saveClicked.subscribe(_ => this.save());
                tb.saveCloneClicked.subscribe(_ => this.save(true));
                tb.printClicked.subscribe(_ => this.printPatron());
            }
        }
    }

    get toolbar(): EditToolbarComponent {
        return this._toolbar;
    }

    @ViewChild('profileSelect')
    private profileSelect: ProfileSelectComponent;
    @ViewChild('secondaryGroupsDialog')
    private secondaryGroupsDialog: SecondaryGroupsDialogComponent;
    @ViewChild('holdNotifyUpdateDialog')
    private holdNotifyUpdateDialog: HoldNotifyUpdateDialogComponent;
    @ViewChild('addrAlert') private addrAlert: AlertDialogComponent;
    @ViewChild('addrRequiredAlert')
    private addrRequiredAlert: AlertDialogComponent;
    @ViewChild('xactCollisionAlert')
    private xactCollisionAlert: AlertDialogComponent;


    autoId = -1;
    patron: IdlObject;
    modifiedPatron: IdlObject;
    changeHandlerNeeded = false;
    nameTab = 'primary';
    replaceBarcodeUsed = false;

    // Are we still fetching data and applying values?
    loading = false;
    // Should the user be able to see the form?
    // On page load, we want to show the form just before we are
    // done loading, so values can be applied to inputs after they
    // are rendered but before those changes would result in setting
    // changesPending = true
    showForm = false;

    surveys: IdlObject[];
    smsCarriers: ComboboxEntry[];
    identTypes: ComboboxEntry[];
    inetLevels: ComboboxEntry[];
    statCats: StatCat[] = [];
    grpList: IdlObject;
    editProfiles: IdlObject[] = [];
    userStatCats: {[statId: number]: ComboboxEntry} = {};
    userSettings: {[name: string]: any} = {};
    userSettingTypes: {[name: string]: IdlObject} = {};
    optInSettingTypes: {[name: string]: IdlObject} = {};
    secondaryGroups: IdlObject[] = [];
    expireDate: Date;
    changesPending = false;
    dupeBarcode = false;
    dupeUsername = false;
    origUsername: string;
    stageUser: IdlObject;
    stageUserRequestor: IdlObject;
    waiverName: string;

    fieldPatterns: {[cls: string]: {[field: string]: RegExp}} = {
        au: {},
        ac: {},
        aua: {},
        aus: {}
    };

    fieldVisibility: {[key: string]: FieldVisibility} = {};

    holdNotifyValues = {
        day_phone: null,
        other_phone: null,
        evening_phone: null,
        default_phone: null,
        default_sms_notify: null,
        default_sms_carrier: null,
        phone_notify: false,
        email_notify: false,
        sms_notify: false
    };

    // All locations we have the specified permissions
    permOrgs: {[name: string]: number[]};

    // True if a given perm is granted at the current home_ou of the
    // patron we are editing.
    hasPerm: {[name: string]: boolean} = {};

    holdNotifyTypes: {email?: boolean, phone?: boolean, sms?: boolean} = {};

    fieldDoc: {[cls: string]: {[field: string]: string}} = {};

    constructor(
        private router: Router,
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private idl: IdlService,
        private strings: StringService,
        private toast: ToastService,
        private perms: PermService,
        private evt: EventService,
        private serverStore: ServerStoreService,
        private broadcaster: BroadcastService,
        private patronService: PatronService,
        private printer: PrintService,
        private worklog: WorkLogService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
        this.load();
    }

    load(): Promise<any> {
        this.loading = true;
        this.showForm = false;
        return this.setStatCats()
            .then(_ => this.getFieldDocs())
            .then(_ => this.setSurveys())
            .then(_ => this.loadPatron())
            .then(_ => this.getCloneUser())
            .then(_ => this.getStageUser())
            .then(_ => this.getSecondaryGroups())
            .then(_ => this.applyPerms())
            .then(_ => this.setEditProfiles())
            .then(_ => this.setIdentTypes())
            .then(_ => this.setInetLevels())
            .then(_ => this.setOptInSettings())
            .then(_ => this.setSmsCarriers())
            .then(_ => this.setFieldPatterns())
            .then(_ => this.showForm = true)
        // Not my preferred way to handle this, but some values are
        // applied to widgets slightly after the load() is done and the
        // widgets are rendered.  If a widget is required and has no
        // value yet, then a premature save state check will see the
        // form as invalid and nonsaveable. In order the check for a
        // non-saveable state on page load without forcing the page into
        // an nonsaveable state on every page load, check the save state
        // after a 1 second delay.
            .then(_ => setTimeout(() => {
                this.emitSaveState();
                this.loading = false;
            }, 1000));
    }

    setEditProfiles(): Promise<any> {
        return this.pcrud.retrieveAll('pgt', {}, {atomic: true}).toPromise()
            .then(list => this.grpList = list)
            .then(_ => this.applyEditProfiles());
    }

    // TODO
    // Share the set of forbidden groups with the 2ndary groups selector.
    applyEditProfiles(): Promise<any> {
        const appPerms = [];
        const failedPerms = [];
        const profiles = this.grpList;

        // extract the application permissions
        profiles.forEach(grp => {
            if (grp.application_perm()) {
                appPerms.push(grp.application_perm());
            }
        });

        const traverseTree = (grp: IdlObject, failed: boolean) => {
            if (!grp) { return; }

            failed = failed || failedPerms.includes(grp.application_perm());

            if (!failed) { this.editProfiles.push(grp.id()); }

            const children = profiles.filter(p => p.parent() === grp.id());
            children.forEach(child => traverseTree(child, failed));
        };

        return this.perms.hasWorkPermAt(appPerms, true).then(orgs => {
            appPerms.forEach(p => {
                if (orgs[p].length === 0) { failedPerms.push(p); }
                traverseTree(this.grpList[0], false);
            });
        });
    }

    getCloneUser(): Promise<any> {
        if (!this.cloneId) { return Promise.resolve(); }

        return this.patronService.getById(this.cloneId,
            {flesh: 1, flesh_fields: {au: ['addresses']}})
            .then(cloneUser => {
                const evt = this.evt.parse(cloneUser);
                if (evt) { return alert(evt); }
                this.copyCloneData(cloneUser);
            });
    }

    getStageUser(): Promise<any> {
        if (!this.stageUsername) { return Promise.resolve(); }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.stage.retrieve.by_username',
            this.auth.token(), this.stageUsername).toPromise()

            .then(suser => {
                const evt = this.evt.parse(suser);
                if (evt) {
                    alert(evt);
                    return Promise.reject(evt);
                } else {
                    this.stageUser = suser;
                }
            })
            .then(_ => {

                const requestor = this.stageUser.user.requesting_usr();
                if (requestor) {
                    return this.pcrud.retrieve('au', requestor).toPromise();
                }

            })
            .then(reqr => this.stageUserRequestor = reqr)
            .then(_ => this.copyStageData())
            .then(_ => this.maintainJuvFlag());
    }

    copyStageData() {
        const stageData = this.stageUser;
        const patron = this.patron;

        Object.keys(this.idl.classes.stgu.field_map).forEach(key => {
            const field = this.idl.classes.au.field_map[key];
            if (field && !field.virtual) {
                const value = stageData.user[key]();
                if (value !== null) {
                    patron[key](value);
                }
            }
        });

        // Clear the usrname if it looks like a UUID
        if (patron.usrname().replace(/-/g, '').match(/[0-9a-f]{32}/)) {
            patron.usrname('');
        }

        // Don't use stub address if we have one from the staged user.
        if (stageData.mailing_addresses.length > 0
            || stageData.billing_addresses.length > 0) {
            patron.addresses([]);
        }

        const addrFromStage = (stageAddr: IdlObject) => {
            if (!stageAddr) { return; }

            const cls = stageAddr.classname;
            const addr = this.idl.create('aua');

            addr.isnew(true);
            addr.id(this.autoId--);
            addr.valid('t');

            this.strings.interpolate('circ.patron.edit.default_addr_type')
                .then(msg => addr.address_type(msg));

            Object.keys(this.idl.classes[cls].field_map).forEach(key => {
                const field = this.idl.classes.aua.field_map[key];
                if (field && !field.virtual) {
                    const value = stageAddr[key]();
                    if (value !== null) {
                        addr[key](value);
                    }
                }
            });

            patron.addresses().push(addr);

            if (cls === 'stgma') {
                patron.mailing_address(addr);
            } else {
                patron.billing_address(addr);
            }
        };

        addrFromStage(stageData.mailing_addresses[0]);
        addrFromStage(stageData.billing_addresses[0]);

        if (patron.addresses().length === 1) {
            // Only one address, use it for both purposes.
            const addr = patron.addresses()[0];
            patron.mailing_address(addr);
            patron.billing_address(addr);
        }

        if (stageData.cards[0]) {
            const card = this.idl.create('ac');
            card.isnew(true);
            card.id(this.autoId--);
            card.barcode(stageData.cards[0].barcode());
            patron.card(card);
            patron.cards([card]);

            if (!patron.usrname()) {
                patron.usrname(card.barcode());
            }
        }

        stageData.settings.forEach(setting => {
            this.userSettings[setting.setting()] = Boolean(setting.value());
        });

        stageData.statcats.forEach(entry => {

            entry.statcat(Number(entry.statcat()));

            const stat: StatCat =
                this.statCats.filter(s => s.cat.id() === entry.statcat())[0];

            let cboxEntry: ComboboxEntry =
                stat.entries.filter(e => e.label === entry.value())[0];

            if (!cboxEntry) {
                // If the applied value is not in the list of entries,
                // create a freetext combobox entry for it.
                cboxEntry = {
                    id: null,
                    freetext: true,
                    label: entry.value()
                };

                stat.entries.unshift(cboxEntry);
            }

            this.userStatCats[entry.statcat()] = cboxEntry;

            // This forces the creation of the stat cat entry IDL objects.
            this.userStatCatChange(stat.cat, cboxEntry);
        });

        if (patron.billing_address()) {
            this.handlePostCodeChange(
                patron.billing_address(), patron.billing_address().post_code());
        }
    }

    checkStageUserDupes(): Promise<any> {
        // Fire duplicate patron checks,once for each category

        const patron = this.patron;

        // Fire-and-forget the email search because it can take several seconds
        if (patron.email()) {
            this.dupeValueChange('email', patron.email());
        }

        return this.dupeValueChange('name', patron.family_name())

            .then(_ => {
                if (patron.ident_value()) {
                    return this.dupeValueChange('ident', patron.ident_value());
                }
            })
            .then(_ => {
                if (patron.day_phone()) {
                    return this.dupeValueChange('phone', patron.day_phone());
                }
            })
            .then(_ => {
                let promise = Promise.resolve();
                this.patron.addresses().forEach(addr => {
                    promise =
                    promise.then(__ => this.dupeValueChange('address', addr));
                    promise =
                    promise.then(__ => this.toolbar.checkAddressAlerts(patron, addr));
                });
            });
    }

    copyCloneData(clone: IdlObject) {
        const patron = this.patron;

        // flesh the home org locally
        patron.home_ou(clone.home_ou());

        ['day_phone', 'evening_phone', 'other_phone', 'usrgroup']
            .forEach(field => patron[field](clone[field]()));

        // Create a new address from an existing address
        const cloneAddr = (addr: IdlObject) => {
            const newAddr = this.idl.clone(addr);
            newAddr.id(this.autoId--);
            newAddr.usr(patron.id());
            newAddr.isnew(true);
            newAddr.valid('t');
            return newAddr;
        };

        const copyAddrs =
            this.context.settingsCache['circ.patron_edit.clone.copy_address'];

        // No addresses to copy/link.  Stick with the defaults.
        if (clone.addresses().length === 0) { return; }

        patron.addresses([]);

        clone.addresses().forEach(sourceAddr => {

            const myAddr = copyAddrs ? cloneAddr(sourceAddr) : sourceAddr;
            if (copyAddrs) { myAddr._linked_owner = clone; }

            if (clone.billing_address() === sourceAddr.id()) {
                this.patron.billing_address(myAddr);
            }

            if (clone.mailing_address() === sourceAddr.id()) {
                this.patron.mailing_address(myAddr);
            }

            this.patron.addresses().push(myAddr);
        });

        // If we have one type of address but not the other, use the one
        // we have for both address purposes.

        if (!this.patron.billing_address() && this.patron.mailing_address()) {
            this.patron.billing_address(this.patron.mailing_address());
        }

        if (this.patron.billing_address() && !this.patron.mailing_address()) {
            this.patron.mailing_address(this.patron.billing_address());
        }
    }

    getFieldDocs(): Promise<any> {
        return this.pcrud.search('fdoc', {
            fm_class: ['au', 'ac', 'aua', 'actsc', 'asv', 'asvq', 'asva']})
            .pipe(tap(doc => {
                if (!this.fieldDoc[doc.fm_class()]) {
                    this.fieldDoc[doc.fm_class()] = {};
                }
                this.fieldDoc[doc.fm_class()][doc.field()] = doc.string();
            })).toPromise();
    }

    getFieldDoc(cls: string, field: string): string {
        cls = this.getClass(cls);
        if (this.fieldDoc[cls]) {
            return this.fieldDoc[cls][field];
        }
    }

    exampleText(cls: string, field: string): string {
        cls = this.getClass(cls);
        return this.context.settingsCache[`ui.patron.edit.${cls}.${field}.example`];
    }

    setSurveys(): Promise<any> {
        return this.patronService.getSurveys()
            .then(surveys => this.surveys = surveys);
    }

    surveyQuestionAnswers(question: IdlObject): ComboboxEntry[] {
        return question.answers().map(
            a => ({id: a.id(), label: a.answer(), fm: a}));
    }

    setStatCats(): Promise<any> {
        this.statCats = [];
        return this.patronService.getStatCats().then(cats => {
            cats.forEach(cat => {
                cat.id(Number(cat.id()));
                cat.entries().forEach(entry => entry.id(Number(entry.id())));

                const entries = cat.entries().map(entry =>
                    ({id: entry.id(), label: entry.value()}));

                this.statCats.push({
                    cat: cat,
                    entries: entries
                });
            });
        });
    }

    setSmsCarriers(): Promise<any> {
        if (!this.context.settingsCache['sms.enable']) {
            return Promise.resolve();
        }

        return this.patronService.getSmsCarriers().then(carriers => {
            this.smsCarriers = carriers.map(carrier => {
                return {
                    id: carrier.id(),
                    label: carrier.name()
                };
            });
        });
    }

    getSecondaryGroups(): Promise<any> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.get_groups',
            this.auth.token(), this.patronId

        ).pipe(concatMap(maps => {
            if (maps.length === 0) { return []; }

            return this.pcrud.search('pgt',
                {id: maps.map(m => m.grp())}, {}, {atomic: true});

        })).pipe(tap(grps => this.secondaryGroups = grps)).toPromise();
    }

    setIdentTypes(): Promise<any> {
        return this.patronService.getIdentTypes()
            .then(types => {
                this.identTypes = types.map(t => ({id: t.id(), label: t.name()}));
            });
    }

    setInetLevels(): Promise<any> {
        return this.patronService.getInetLevels()
            .then(levels => {
                this.inetLevels = levels.map(t => ({id: t.id(), label: t.name()}));
            });
    }

    applyPerms(): Promise<any> {

        const promise = this.permOrgs ?
            Promise.resolve(this.permOrgs) :
            this.perms.hasWorkPermAt(PERMS_NEEDED, true);

        return promise.then(permOrgs => {
            this.permOrgs = permOrgs;
            Object.keys(permOrgs).forEach(perm =>
                this.hasPerm[perm] =
                  permOrgs[perm].includes(this.patron.home_ou())
            );
        });
    }

    setOptInSettings(): Promise<any> {
        const orgIds = this.org.ancestors(this.auth.user().ws_ou(), true);

        const query = {
            '-or' : [
                {name : COMMON_USER_SETTING_TYPES},
                {name : { // opt-in notification user settings
                    'in': {
                        select : {atevdef : ['opt_in_setting']},
                        from : 'atevdef',
                        // we only care about opt-in settings for
                        // event_defs our users encounter
                        where : {'+atevdef' : {owner : orgIds}}
                    }
                }}
            ]
        };

        return this.pcrud.search('cust', query, {}, {atomic : true})
            .toPromise().then(types => {

                types.forEach(stype => {
                    this.userSettingTypes[stype.name()] = stype;
                    if (!COMMON_USER_SETTING_TYPES.includes(stype.name())) {
                        this.optInSettingTypes[stype.name()] = stype;
                    }

                    if (this.patron.isnew()) {
                        let val = stype.reg_default();
                        if (val !== null && val !== undefined) {
                            if (stype.datatype() === 'bool') {
                            // A boolean user setting type whose default
                            // value starts with t/T is considered 'true',
                            // false otherwise.
                                val = Boolean((val + '').match(/^t/i));
                            }
                            this.userSettings[stype.name()] = val;
                        }
                    }
                });
            });
    }

    loadPatron(): Promise<any> {
        if (this.patronId) {
            return this.patronService.getFleshedById(this.patronId, PATRON_FLESH_FIELDS)
                .then(patron => {
                    this.patron = patron;
                    this.origUsername = patron.usrname();
                    this.absorbPatronData();
                });
        } else {
            return Promise.resolve(this.createNewPatron());
        }
    }

    absorbPatronData() {

        const usets = this.userSettings;
        let setting;

        this.holdNotifyValues.day_phone = this.patron.day_phone();
        this.holdNotifyValues.other_phone = this.patron.other_phone();
        this.holdNotifyValues.evening_phone = this.patron.evening_phone();

        this.patron.settings().forEach(stg => {
            const value = stg.value();
            if (value !== '' && value !== null) {
                usets[stg.name()] = JSON.parse(value);
            }
        });

        const holdNotify = usets['opac.hold_notify'];

        if (holdNotify) {
            this.holdNotifyTypes.email = this.holdNotifyValues.email_notify
                = holdNotify.match(/email/) !== null;

            this.holdNotifyTypes.phone = this.holdNotifyValues.phone_notify
                = holdNotify.match(/phone/) !== null;

            this.holdNotifyTypes.sms = this.holdNotifyValues.sms_notify
                = holdNotify.match(/sms/) !== null;
        }

        if (setting = usets['opac.default_sms_carrier']) {
            setting = usets['opac.default_sms_carrier'] = Number(setting);
            this.holdNotifyValues.default_sms_carrier = setting;
        }

        if (setting = usets['opac.default_phone']) {
            this.holdNotifyValues.default_phone = setting;
        }

        if (setting = usets['opac.default_sms_notify']) {
            this.holdNotifyValues.default_sms_notify = setting;
        }

        if (setting = usets['opac.default_pickup_location']) {
            usets['opac.default_pickup_location'] = Number(setting);
        }

        this.expireDate = new Date(this.patron.expire_date());

        // stat_cat_entries() are entry maps under the covers.
        this.patron.stat_cat_entries().forEach(map => {

            const stat: StatCat =
                this.statCats.filter(s => s.cat.id() === map.stat_cat())[0];

            let cboxEntry: ComboboxEntry =
                stat.entries.filter(e => e.label === map.stat_cat_entry())[0];

            if (!cboxEntry) {
                // If the applied value is not in the list of entries,
                // create a freetext combobox entry for it.
                cboxEntry = {
                    id: null,
                    freetext: true,
                    label: map.stat_cat_entry(),
                    fm: map
                };

                stat.entries.unshift(cboxEntry);
            }

            this.userStatCats[map.stat_cat()] = cboxEntry;
        });

        if (this.patron.waiver_entries().length === 0) {
            this.addWaiver();
        }

        if (!this.patron.card()) {
            this.replaceBarcode();
        }
    }

    createNewPatron() {
        const patron = this.idl.create('au');
        patron.isnew(true);
        patron.id(-1);
        patron.home_ou(this.auth.user().ws_ou());
        patron.active('t');
        patron.settings([]);
        patron.waiver_entries([]);
        patron.stat_cat_entries([]);

        const card = this.idl.create('ac');
        card.isnew(true);
        card.usr(-1);
        card.id(this.autoId--);
        patron.card(card);
        patron.cards([card]);

        const addr = this.idl.create('aua');
        addr.isnew(true);
        addr.id(-1);
        addr.usr(-1);
        addr.valid('t');
        addr.within_city_limits('f');
        addr.country(this.context.settingsCache['ui.patron.default_country']);
        patron.billing_address(addr);
        patron.mailing_address(addr);
        patron.addresses([addr]);

        this.strings.interpolate('circ.patron.edit.default_addr_type')
            .then(msg => addr.address_type(msg));

        this.serverStore.getItem('ui.patron.default_ident_type')
            .then(identType => {
                if (identType) { patron.ident_type(Number(identType)); }
            });

        this.patron = patron;
        this.addWaiver();
    }

    objectFromPath(path: string, index: number): IdlObject {
        const base = path ? this.patron[path]() : this.patron;
        if (index === null || index === undefined) {
            return base;
        } else {
            // Some paths lead to an array of objects.
            return base[index];
        }
    }

    getFieldLabel(idlClass: string, field: string, override?: string): string {
        return override ? override :
            this.idl.classes[idlClass].field_map[field].label;
    }

    // With this, the 'cls' specifier is only needed in the template
    // when it's not 'au', which is the base/common class.
    getClass(cls: string): string {
        return cls || 'au';
    }

    getFieldValue(path: string, index: number, field: string): any {
        return this.objectFromPath(path, index)[field]();
    }

    emitSaveState() {
        // Timeout gives the form a chance to mark fields as (in)valid
        setTimeout(() => {

            const invalidInput = document.querySelector('.ng-invalid');

            const canSave = (
                invalidInput === null
                && !this.dupeBarcode
                && !this.dupeUsername
                && !this.selfEditForbidden()
                && !this.groupEditForbidden()
            );

            if (this.toolbar) {
                this.toolbar.disableSaveStateChanged.emit(!canSave);
            }
        });
    }

    adjustSaveState() {
        // Avoid responding to any value changes while we are loading
        if (this.loading) { return; }
        this.changesPending = true;
        this.emitSaveState();
    }

    userStatCatChange(cat: IdlObject, entry: ComboboxEntry) {
        let map = this.patron.stat_cat_entries()
            .filter(m => m.stat_cat() === cat.id())[0];

        if (map) {
            if (entry) {
                map.stat_cat_entry(entry.label);
                map.ischanged(true);
                map.isdeleted(false);
            } else {
                if (map.isnew()) {
                    // Deleting a stat cat that was created during this
                    // edit session just means removing it from the list
                    // of maps to consider.
                    this.patron.stat_cat_entries(
                        this.patron.stat_cat_entries()
                            .filter(m => m.stat_cat() !== cat.id())
                    );
                } else {
                    map.isdeleted(true);
                }
            }
        } else {
            map = this.idl.create('actscecm');
            map.isnew(true);
            map.stat_cat(cat.id());
            map.stat_cat_entry(entry.label);
            map.target_usr(this.patronId);
            this.patron.stat_cat_entries().push(map);
        }

        this.adjustSaveState();
    }

    userSettingChange(name: string, value: any) {
        this.userSettings[name] = value;
        this.adjustSaveState();
    }

    applySurveyResponse(question: IdlObject, answer: ComboboxEntry) {
        if (!this.patron.survey_responses()) {
            this.patron.survey_responses([]);
        }

        const responses = this.patron.survey_responses()
            .filter(r => r.question() !== question.id());

        const resp = this.idl.create('asvr');
        resp.isnew(true);
        resp.survey(question.survey());
        resp.question(question.id());
        resp.answer(answer.id);
        resp.usr(this.patron.id());
        resp.answer_date('now');
        responses.push(resp);
        this.patron.survey_responses(responses);
    }

    // Called as the model changes.
    // This may be called many times before the final value is applied,
    // so avoid any heavy lifting here.  See afterFieldChange();
    fieldValueChange(path: string, index: number, field: string, value: any) {
        if (typeof value === 'boolean') { value = value ? 't' : 'f'; }

        // This can be called in cases where components fire up, even
        // though the actual value on the patron has not changed.
        // Exit early in that case so we don't mark the form as dirty.
        const oldValue = this.getFieldValue(path, index, field);
        if (oldValue === value) { return; }

        this.changeHandlerNeeded = true;
        this.objectFromPath(path, index)[field](value);
    }

    // Called after a change operation has completed (e.g. on blur)
    afterFieldChange(path: string, index: number, field: string) {
        if (!this.changeHandlerNeeded) { return; } // no changes applied
        this.changeHandlerNeeded = false;

        const obj = this.objectFromPath(path, index);
        const value = this.getFieldValue(path, index, field);
        obj.ischanged(true); // isnew() supersedes

        console.debug(
            `Modifying field path=${path || ''} field=${field} value=${value}`);

        switch (field) {

            case 'dob':
                this.maintainJuvFlag();
                break;

            case 'profile':
                this.setExpireDate();
                break;

            case 'day_phone':
            case 'evening_phone':
            case 'other_phone':
                this.handlePhoneChange(field, value);
                break;

            case 'ident_value':
            case 'ident_value2':
            case 'first_given_name':
            case 'family_name':
            case 'email':
                this.dupeValueChange(field, value);
                break;

            case 'street1':
            case 'street2':
            case 'city':
                // dupe search on address wants the address object as the value.
                this.dupeValueChange('address', obj);
                this.toolbar.checkAddressAlerts(this.patron, obj);
                break;

            case 'post_code':
                this.handlePostCodeChange(obj, value);
                break;

            case 'barcode':
                this.handleBarcodeChange(value);
                break;

            case 'usrname':
                this.handleUsernameChange(value);
                break;
        }

        this.adjustSaveState();
    }

    maintainJuvFlag() {

        if (!this.patron.dob()) { return; }

        const interval =
            this.context.settingsCache['global.juvenile_age_threshold']
            || '18 years';

        const cutoff = new Date();

        cutoff.setTime(cutoff.getTime() -
            Number(DateUtil.intervalToSeconds(interval) + '000'));

        const isJuve = new Date(this.patron.dob()) > cutoff;

        this.fieldValueChange(null, null, 'juvenile', isJuve);
        this.afterFieldChange(null, null, 'juvenile');
    }

    handlePhoneChange(field: string, value: string) {
        this.dupeValueChange(field, value);

        const pwUsePhone =
            this.context.settingsCache['patron.password.use_phone'];

        if (field === 'day_phone' && value &&
            this.patron.isnew() && !this.patron.passwd() && pwUsePhone) {
            this.fieldValueChange(null, null, 'passwd', value.substr(-4));
            this.afterFieldChange(null, null, 'passwd');
        }
    }

    handlePostCodeChange(addr: IdlObject, postCode: any) {
        this.net.request(
            'open-ils.search', 'open-ils.search.zip', postCode
        ).subscribe(resp => {
            if (!resp) { return; }

            ['city', 'state', 'county'].forEach(field => {
                if (resp[field]) {
                    addr[field](resp[field]);
                }
            });

            if (resp.alert) {
                this.addrAlert.dialogBody = resp.alert;
                this.addrAlert.open();
            }
        });
    }

    handleUsernameChange(value: any) {
        this.dupeUsername = false;

        if (!value || value === this.origUsername) {
            // In case the usrname changes then changes back.
            return;
        }

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.username.exists',
            this.auth.token(), value
        ).subscribe(resp => this.dupeUsername = Boolean(resp));
    }

    handleBarcodeChange(value: any) {
        this.dupeBarcode = false;

        if (!value) { return; }

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.barcode.exists',
            this.auth.token(), value
        ).subscribe(resp => {
            if (Number(resp) === 1) {
                this.dupeBarcode = true;
            } else {

                if (this.patron.usrname()) { return; }

                // Propagate username with barcode value by default.
                // This will apply the value and fire the dupe checker
                this.updateUsernameRegex();
                this.fieldValueChange(null, null, 'usrname', value);
                this.afterFieldChange(null, null, 'usrname');
            }
        });
    }

    dupeValueChange(name: string, value: any): Promise<any> {

        if (name.match(/phone/)) { name = 'phone'; }
        if (name.match(/name/)) { name = 'name'; }
        if (name.match(/ident/)) { name = 'ident'; }

        let search: PatronSearchFieldSet;
        switch (name) {

            case 'name':
                const fname = this.patron.first_given_name();
                const lname = this.patron.family_name();
                if (!fname || !lname) { return; }
                search = {
                    first_given_name : {value : fname, group : 0},
                    family_name : {value : lname, group : 0}
                };
                break;

            case 'email':
                search = {email : {value : value, group : 0}};
                break;

            case 'ident':
                search = {ident : {value : value, group : 2}};
                break;

            case 'phone':
                search = {phone : {value : value, group : 2}};
                break;

            case 'address':
                search = {};
                ['street1', 'street2', 'city', 'post_code'].forEach(field => {
                    if (value[field]()) {
                        search[field] = {value : value[field](), group: 1};
                    }
                });
                break;
        }

        return this.toolbar.checkDupes(name, search);
    }

    showField(field: string): boolean {

        if (this.fieldVisibility[field] === undefined) {
            // Settings have not yet been applied for this field.
            // Calculate them now.

            // The preferred name fields use the primary name field settings
            let settingKey = field;
            let altName = false;
            if (field.match(/^au.alt_/)) {
                altName = true;
                settingKey = field.replace(/alt_/, '');
            }

            const required = `ui.patron.edit.${settingKey}.require`;
            const show = `ui.patron.edit.${settingKey}.show`;
            const suggest = `ui.patron.edit.${settingKey}.suggest`;

            if (this.context.settingsCache[required]) {
                if (altName) {
                    // Preferred name fields are never required.
                    this.fieldVisibility[field] = FieldVisibility.VISIBLE;
                } else {
                    this.fieldVisibility[field] = FieldVisibility.REQUIRED;
                }

            } else if (this.context.settingsCache[show]) {
                this.fieldVisibility[field] = FieldVisibility.VISIBLE;

            } else if (this.context.settingsCache[suggest]) {
                this.fieldVisibility[field] = FieldVisibility.SUGGESTED;
            }
        }

        if (this.fieldVisibility[field] === undefined) {
            // No org settings were applied above.  Use the default
            // settings if present or assume the field has no
            // visibility flags applied.
            this.fieldVisibility[field] = DEFAULT_FIELD_VISIBILITY[field] || 0;
        }

        return this.fieldVisibility[field] >= this.toolbar.visibilityLevel;
    }

    fieldRequired(field: string): boolean {

        switch (field) {
            case 'au.passwd':
                // Only required for new patrons
                return this.patronId === null;

            case 'au.email':
                // If the user ops in for email notices, require
                // an email address
                return this.holdNotifyTypes.email;
        }

        return this.fieldVisibility[field] === 3;
    }

    settingFieldRequired(name: string): boolean {

        switch (name) {
            case 'opac.default_sms_notify':
            case 'opac.default_sms_carrier':
                return this.holdNotifyTypes.sms;
        }

        return false;
    }

    fieldPattern(idlClass: string, field: string): RegExp {
        if (!this.fieldPatterns[idlClass][field]) {
            this.fieldPatterns[idlClass][field] = new RegExp('.*');
        }
        return this.fieldPatterns[idlClass][field];
    }

    generatePassword() {
        this.fieldValueChange(null, null,
            'passwd', Math.floor(Math.random() * 9000) + 1000);

        // Normally this is called on (blur), but the input is not
        // focused when using the generate button.
        this.afterFieldChange(null, null, 'passwd');
    }


    cannotHaveUsersOrgs(): number[] {
        return this.org.list()
            .filter(org => org.ou_type().can_have_users() === 'f')
            .map(org => org.id());
    }

    cannotHaveVolsOrgs(): number[] {
        return this.org.list()
            .filter(org => org.ou_type().can_have_vols() === 'f')
            .map(org => org.id());
    }

    setExpireDate() {
        const profile = this.profileSelect.profiles[this.patron.profile()];
        if (!profile) { return; }

        const seconds = DateUtil.intervalToSeconds(profile.perm_interval());
        const nowEpoch = new Date().getTime();
        const newDate = new Date(nowEpoch + (seconds * 1000 /* millis */));
        this.expireDate = newDate;
        this.fieldValueChange(null, null, 'expire_date', newDate.toISOString());
        this.afterFieldChange(null, null, 'expire_date');
    }

    handleBoolResponse(success: boolean,
        msg: string, errMsg?: string): Promise<boolean> {

        if (success) {
            return this.strings.interpolate(msg)
                .then(str => this.toast.success(str))
                .then(_ => true);
        }

        console.error(errMsg);

        return this.strings.interpolate(msg)
            .then(str => this.toast.danger(str))
            .then(_ => false);
    }

    sendTestMessage(hook: string): Promise<boolean> {

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.event.test_notification',
            this.auth.token(), {hook: hook, target: this.patronId}
        ).toPromise().then(resp => {

            if (resp && resp.template_output && resp.template_output() &&
                resp.template_output().is_error() === 'f') {
                return this.handleBoolResponse(
                    true, 'circ.patron.edit.test_notify.success');

            } else {
                return this.handleBoolResponse(
                    false, 'circ.patron.edit.test_notify.fail',
                    'Test Notification Failed ' + resp);
            }
        });
    }

    invalidateField(field: string): Promise<boolean> {

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.invalidate.' + field,
            this.auth.token(), this.patronId, null, this.patron.home_ou()

        ).toPromise().then(resp => {
            const evt = this.evt.parse(resp);

            if (evt && evt.textcode !== 'SUCCESS') {
                return this.handleBoolResponse(false,
                    'circ.patron.edit.invalidate.fail',
                    'Field Invalidation Failed: ' + resp);
            }

            this.patron[field](null);

            // Keep this in sync for future updates.
            this.patron.last_xact_id(resp.payload.last_xact_id[this.patronId]);

            return this.handleBoolResponse(
                true, 'circ.patron.edit.invalidate.success');
        });
    }

    openGroupsDialog() {
        this.secondaryGroupsDialog.open({size: 'lg'}).subscribe(groups => {
            if (!groups) { return; }

            this.secondaryGroups = groups;

            if (this.patron.isnew()) {
                // Links will be applied after the patron is created.
                return;
            }

            // Apply the new links to an existing user in real time
            this.applySecondaryGroups();
        });
    }

    applySecondaryGroups(): Promise<boolean> {

        const groupIds = this.secondaryGroups.map(grp => grp.id());

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.set_groups',
            this.auth.token(), this.patronId, groupIds
        ).toPromise().then(resp => {

            if (Number(resp) === 1) {
                return this.handleBoolResponse(
                    true, 'circ.patron.edit.grplink.success');

            } else {
                return this.handleBoolResponse(
                    false, 'circ.patron.edit.grplink.fail',
                    'Failed to change group links: ' + resp);
            }
        });
    }

    // Set the mailing or billing address
    setAddrType(addrType: string, addr: IdlObject, selected: boolean) {
        if (selected) {
            this.patron[addrType + '_address'](addr);
        } else {
            // Unchecking mailing/billing means we have to randomly
            // select another address to fill that role.  Select the
            // first address in the list (that does not match the
            // modifed address)
            let found = false;
            this.patron.addresses().some(a => {
                if (a.id() !== addr.id()) {
                    this.patron[addrType + '_address'](a);
                    return found = true;
                }
            });

            if (!found) {
                // No alternate address was found.  Clear the value.
                this.patron[addrType + '_address'](null);
            }

            this.patron.ischanged(true);
        }
    }

    deleteAddr(addr: IdlObject) {
        const addresses = this.patron.addresses();
        let promise = Promise.resolve(false);

        if (this.patron.isnew() && addresses.length === 1) {
            promise = this.serverStore.getItem(
                'ui.patron.registration.require_address');
        }

        promise.then(required => {

            if (required) {
                this.addrRequiredAlert.open();
                return;
            }

            // Roll the mailing/billing designation to another
            // address when needed.
            if (this.patron.mailing_address() &&
                this.patron.mailing_address().id() === addr.id()) {
                this.setAddrType('mailing', addr, false);
            }

            if (this.patron.billing_address() &&
                this.patron.billing_address().id() === addr.id()) {
                this.setAddrType('billing', addr, false);
            }

            if (addr.isnew()) {
                let idx = 0;

                addresses.some((a, i) => {
                    if (a.id() === addr.id()) { idx = i; return true; }
                });

                // New addresses can be discarded
                addresses.splice(idx, 1);

            } else {
                addr.isdeleted(true);
            }
        });
    }

    newAddr() {
        const addr = this.idl.create('aua');
        addr.id(this.autoId--);
        addr.isnew(true);
        addr.valid('t');
        this.patron.addresses().push(addr);
    }

    nonDeletedAddresses(): IdlObject[] {
        return this.patron.addresses().filter(a => !a.isdeleted());
    }

    save(clone?: boolean): Promise<any> {

        this.changesPending = false;
        this.loading = true;
        this.showForm = false;

        return this.saveUser()
            .then(_ => this.saveUserSettings())
            .then(_ => this.updateHoldPrefs())
            .then(_ => this.removeStagedUser())
            .then(_ => this.postSaveRedirect(clone));
    }

    postSaveRedirect(clone: boolean) {

        this.worklog.record({
            user: this.modifiedPatron.family_name(),
            patron_id: this.modifiedPatron.id(),
            action: this.patron.isnew() ? 'registered_patron' : 'edited_patron'
        });

        if (this.stageUser) {
            this.broadcaster.broadcast('eg.pending_usr.update',
                {usr: this.idl.toHash(this.modifiedPatron)});

            // Typically, this window is opened as a new tab from the
            // pending users interface. Once we're done, just close the
            // window.
            window.close();
            return;
        }

        if (clone) {
            this.context.summary = null;
            this.router.navigate(
                ['/staff/circ/patron/register/clone', this.modifiedPatron.id()]);

        } else {
            // Full refresh to force reload of modified patron data.
            window.location.href = window.location.href;
        }
    }

    // Resolves on success, rejects on error
    saveUser(): Promise<IdlObject> {
        this.modifiedPatron = null;

        // A dummy waiver is added on load.  Remove it if no values were added.
        this.patron.waiver_entries(
            this.patron.waiver_entries().filter(e => !e.isnew() || e.name()));

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.update',
            this.auth.token(), this.patron
        ).toPromise().then(result => {

            if (result && result.classname) {
                this.context.addRecentPatron(result.id());

                // Successful result returns the patron IdlObject.
                return this.modifiedPatron = result;
            }

            const evt = this.evt.parse(result);

            if (evt) {
                console.error('Patron update failed with', evt);
                if (evt.textcode === 'XACT_COLLISION') {
                    this.xactCollisionAlert.open().toPromise().then(_ =>
                        window.location.href = window.location.href
                    );
                }
            } else {

                alert('Patron update failed:' + result);
            }

            return Promise.reject('Save Failed');
        });
    }

    // Resolves on success, rejects on error
    saveUserSettings(): Promise<any> {

        let settings: any = {};

        const holdMethods = [];

        ['email', 'phone', 'sms'].forEach(method => {
            if (this.holdNotifyTypes[method]) {
                holdMethods.push(method);
            }
        });

        this.userSettings['opac.hold_notify'] =
            holdMethods.length > 0 ?  holdMethods.join(':') : null;

        if (this.patronId) {
            // Update all user editor setting values for existing
            // users regardless of whether a value changed.
            settings = this.userSettings;

        } else {

            // Create settings for all non-null setting values for new patrons.
            Object.keys(this.userSettings).forEach(key => {
                const val = this.userSettings[key];
                if (val !== null) { settings[key] = val; }
            });
        }

        if (Object.keys(settings).length === 0) { return Promise.resolve(); }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.settings.update',
            this.auth.token(), this.modifiedPatron.id(), settings
        ).toPromise();
    }


    updateHoldPrefs(): Promise<any> {
        if (this.patron.isnew()) { return Promise.resolve(); }

        return this.collectHoldNotifyChange()
            .then(mods => {

                if (mods.length === 0) { return Promise.resolve(); }

                this.holdNotifyUpdateDialog.patronId = this.patronId;
                this.holdNotifyUpdateDialog.mods = mods;
                this.holdNotifyUpdateDialog.smsCarriers = this.smsCarriers;

                this.holdNotifyUpdateDialog.defaultCarrier =
                this.userSettings['opac.default_sms_carrier']
                || this.holdNotifyValues.default_sms_carrier;

                return this.holdNotifyUpdateDialog.open().toPromise();
            });
    }

    // Compare current values with those collected at patron load time.
    // For any that have changed, ask the server if the original values
    // are used on active holds.
    collectHoldNotifyChange(): Promise<any[]> {
        const mods = [];
        const holdNotify = this.userSettings['opac.hold_notify'] || '';

        return from(Object.keys(this.holdNotifyValues))
            .pipe(concatMap(field => {

                let newValue, matches;

                if (field.match(/default_/)) {
                    newValue = this.userSettings[`opac.${field}`] || null;

                } else if (field.match(/_phone/)) {
                    newValue = this.patron[field]();

                } else if (matches = field.match(/(\w+)_notify/)) {
                    const notify = this.userSettings['opac.hold_notify'] || '';
                    newValue = notify.match(matches[1]) !== null;
                }

                const oldValue = this.holdNotifyValues[field];

                // No change to apply?
                if (newValue === oldValue) { return empty(); }

                // API / user setting name mismatch
                if (field.match(/carrier/)) { field += '_id'; }

                const apiValue = field.match(/notify|carrier/) ? oldValue : newValue;

                return this.net.request(
                    'open-ils.circ',
                    'open-ils.circ.holds.retrieve_by_notify_staff',
                    this.auth.token(), this.patronId, apiValue, field
                ).pipe(tap(holds => {
                    if (holds && holds.length > 0) {
                        mods.push({
                            field: field,
                            newValue: newValue,
                            oldValue: oldValue,
                            holds: holds
                        });
                    }
                }));
            })).toPromise().then(_ => mods);
    }

    removeStagedUser(): Promise<any> {
        if (!this.stageUser) { return Promise.resolve(); }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.stage.delete',
            this.auth.token(),
            this.stageUser.user.row_id()
        ).toPromise();
    }

    printPatron() {
        this.printer.print({
            templateName: 'patron_data',
            contextData: {patron: this.patron},
            printContext: 'default'
        });
    }

    replaceBarcode() {
        // Disable current card

        this.replaceBarcodeUsed = true;

        if (this.patron.card()) {
            // patron.card() is not the same in-memory object as its
            // analog in patron.cards().  Since we're about to replace
            // patron.card() anyway, just update the patron.cards() version.
            const crd = this.patron.cards()
                .filter(c => c.id() === this.patron.card().id())[0];

            crd.active('f');
            crd.ischanged(true);
        }

        const card = this.idl.create('ac');
        card.isnew(true);
        card.id(this.autoId--);
        card.usr(this.patron.id());
        card.active('t');

        this.patron.card(card);
        this.patron.cards().push(card);

        // Focus the barcode input
        setTimeout(() => {
            this.emitSaveState();
            const node = document.getElementById('ac-barcode-input');
            node.focus();
        });
    }

    showBarcodes() {
    }

    canSave(): boolean {
        return document.querySelector('.ng-invalid') === null;
    }

    setFieldPatterns() {
        let regex;

        if (regex =
            this.context.settingsCache['ui.patron.edit.ac.barcode.regex']) {
            this.fieldPatterns.ac.barcode = new RegExp(regex);
        }

        if (regex = this.context.settingsCache['global.password_regex']) {
            this.fieldPatterns.au.passwd = new RegExp(regex);
        }

        if (regex = this.context.settingsCache['ui.patron.edit.phone.regex']) {
            // apply generic phone regex first, replace below as needed.
            this.fieldPatterns.au.day_phone = new RegExp(regex);
            this.fieldPatterns.au.evening_phone = new RegExp(regex);
            this.fieldPatterns.au.other_phone = new RegExp(regex);
        }

        // the remaining this.fieldPatterns fit a well-known key name pattern

        Object.keys(this.context.settingsCache).forEach(key => {
            const val = this.context.settingsCache[key];
            if (!val) { return; }
            const parts = key.match(/ui.patron.edit\.(\w+)\.(\w+)\.regex/);
            if (!parts) { return; }
            const cls = parts[1];
            const name = parts[2];
            this.fieldPatterns[cls][name] = new RegExp(val);
        });

        this.updateUsernameRegex();
    }

    // The username must match either the configured regex or the
    // patron's barcode
    updateUsernameRegex() {
        const regex = this.context.settingsCache['opac.username_regex'];
        if (regex) {
            const barcode = this.patron.card().barcode();
            if (barcode) {
                this.fieldPatterns.au.usrname =
                    new RegExp(`${regex}|^${barcode}$`);
            } else {
                // username must match the regex
                this.fieldPatterns.au.usrname = new RegExp(regex);
            }
        } else {
            // username can be any format.
            this.fieldPatterns.au.usrname = new RegExp('.*');
        }
    }

    selfEditForbidden(): boolean {
        return (
            this.patron.id() === this.auth.user().id()
            && !this.hasPerm.EDIT_SELF_IN_CLIENT
        );
    }

    groupEditForbidden(): boolean {
        return (
            this.patron.profile()
            && !this.editProfiles.includes(this.patron.profile())
        );
    }

    addWaiver() {
        const waiver = this.idl.create('aupw');
        waiver.isnew(true);
        waiver.id(this.autoId--);
        waiver.usr(this.patronId);
        this.patron.waiver_entries().push(waiver);
    }

    removeWaiver(waiver: IdlObject) {
        if (waiver.isnew()) {
            this.patron.waiver_entries(
                this.patron.waiver_entries().filter(w => w.id() !== waiver.id()));

            if (this.patron.waiver_entries().length === 0) {
                // We need at least one waiver to access action buttons
                this.addWaiver();
            }
        } else {
            waiver.isdeleted(true);
        }
    }
}


