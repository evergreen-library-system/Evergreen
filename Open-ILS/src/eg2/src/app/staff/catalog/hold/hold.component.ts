import {Component, OnDestroy, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {PermService} from '@eg/core/perm.service';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {StaffCatalogService} from '../catalog.service';
import {HoldsService, HoldRequest,
    HoldRequestTarget} from '@eg/staff/share/holds/holds.service';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronSearchDialogComponent
} from '@eg/staff/share/patron/search-dialog.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {BarcodeSelectComponent
} from '@eg/staff/share/barcodes/barcode-select.component';
import {WorkLogService} from '@eg/staff/share/worklog/worklog.service';
import {getI18nString} from '@eg/share/util/i18ns';
import {StoreService} from '@eg/core/store.service';
import {firstValueFrom} from 'rxjs';

class HoldContext {
    holdMeta: HoldRequestTarget;
    holdTarget: number;
    lastRequest: HoldRequest;
    canOverride?: boolean;
    processing: boolean;
    selectedFormats: any;
    success = false;

    constructor(target: number) {
        this.holdTarget = target;
        this.processing = false;
        this.selectedFormats = {
            // code => selected-boolean
            formats: {},
            langs: {}
        };
    }

    clone(target: number): HoldContext {
        const ctx = new HoldContext(target);
        ctx.holdMeta = this.holdMeta;
        return ctx;
    }
}

@Component({
    templateUrl: 'hold.component.html'
})
export class HoldComponent implements OnInit, OnDestroy {

    holdType: string;
    holdTargets: number[];
    user: IdlObject; //
    userBarcode: string;
    requestor: IdlObject;
    holdFor: string;
    pickupLib: number;
    notifyEmail: boolean;
    notifyPhone: boolean;
    phoneValue: string;
    notifySms: boolean;
    smsValue: string;
    suspend: boolean;
    activeDateStr: string;
    activeDateYmd: string;
    activeDate: Date;
    activeDateInvalid = false;
    anyPartLabel = $localize`All Parts`;

    holdContexts: HoldContext[];
    recordSummaries: BibRecordSummary[];

    currentUserBarcode: string;
    smsCarriers: ComboboxEntry[];
    userBarcodeTimeout: any;

    smsEnabled: boolean;

    maxMultiHolds = 0;

    // True if mult-copy holds are active for the current receipient.
    multiHoldsActive = false;

    canPlaceMultiAt: number[] = [];
    multiHoldCount = 1;
    placeHoldsClicked: boolean;
    badBarcode: string = null;

    puLibWsFallback = false;
    puLibWsDefault = false;

    // Orgs which are not valid pickup locations
    disableOrgs: number[] = [];

    // Default is 1, but wait for settings to load
    // in case this feature isn't enabled for holds.
    maxRecentPatrons = 0;
    recentPatronIds: number[] = [];

    @ViewChild('patronSearch', {static: false})
        patronSearch: PatronSearchDialogComponent;

    @ViewChild('smsCbox', {static: false}) smsCbox: ComboboxComponent;
    @ViewChild('barcodeSelect') private barcodeSelect: BarcodeSelectComponent;

    @ViewChild('activeDateAlert') private activeDateAlert: AlertDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private evt: EventService,
        private net: NetService,
        private org: OrgService,
        private store: ServerStoreService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private bib: BibRecordService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService,
        private holds: HoldsService,
        private patron: PatronService,
        private perm: PermService,
        private worklog: WorkLogService,
        private sessionStore: StoreService
    ) {
        this.holdContexts = [];
        this.smsCarriers = [];
    }

    ngOnInit() {

        // Respond to changes in hold type.  This currently assumes hold
        // types only toggle post-init between copy-level types (C,R,F)
        // and no other params (e.g. target) change with it.  If other
        // types require tracking, additional data collection may be needed.
        this.route.paramMap.subscribe(
            (params: ParamMap) => this.holdType = params.get('type'));

        this.holdType = this.route.snapshot.params['type'];
        this.holdTargets = this.route.snapshot.queryParams['target'];
        this.holdFor = this.route.snapshot.queryParams['holdFor'] || 'patron';

        if (this.staffCat.holdForBarcode) {
            this.holdFor = 'patron';
            this.userBarcode = this.staffCat.holdForBarcode;
        }

        this.store.getItemBatch([
            'circ.staff_placed_holds_fallback_to_ws_ou',
            'circ.staff_placed_holds_default_to_ws_ou',
            'ui.staff.max_recent_patrons',
            'ui.staff.place_holds_for_recent_patrons'
        ]).then(settings => {
            this.puLibWsFallback =
                settings['circ.staff_placed_holds_fallback_to_ws_ou'] === true;
            this.puLibWsDefault =
                settings['circ.staff_placed_holds_default_to_ws_ou'] === true;

            this.initRecentPatrons(
                !!settings['ui.staff.place_holds_for_recent_patrons'],
                settings['ui.staff.max_recent_patrons'] ?? 1
            );
        }).then(_ => this.worklog.loadSettings());

        this.org.list().forEach(org => {
            if (org.ou_type().can_have_vols() === 'f') {
                this.disableOrgs.push(org.id());
            }
        });

        this.net.request('open-ils.actor',
            'open-ils.actor.settings.value_for_all_orgs',
            null, 'opac.holds.org_unit_not_pickup_lib'
        ).subscribe(resp => {
            if (resp.summary.value) {
                this.disableOrgs.push(Number(resp.org_unit));
            }
        });

        getI18nString(this.pcrud, 1) // Seed data default is: All Parts
            .subscribe(actual_string => {
                this.anyPartLabel = actual_string;
            });

        if (!Array.isArray(this.holdTargets)) {
            this.holdTargets = [this.holdTargets];
        }

        this.holdTargets = this.holdTargets.map(t => Number(t));

        this.requestor = this.auth.user();
        this.pickupLib = this.auth.user().ws_ou();

        this.resetForm();

        this.getRequestorSetsAndPerms()
            .then(_ => {

                // Load receipient data if we have any.
                if (this.staffCat.holdForBarcode) {
                    this.holdFor = 'patron';
                    this.userBarcode = this.staffCat.holdForBarcode;
                }

                if (this.holdFor === 'staff' || this.userBarcode) {
                    this.holdForChanged();
                }
            });

        setTimeout(() => {
            const node = document.getElementById('patron-barcode');
            if (node) { node.focus(); }
        });
    }

    getRequestorSetsAndPerms(): Promise<any> {

        return this.org.settings(
            ['sms.enable', 'circ.holds.max_duplicate_holds'])

            .then(sets => {

                this.smsEnabled = sets['sms.enable'];

                const max = Number(sets['circ.holds.max_duplicate_holds']);
                if (Number(max) > 0) { this.maxMultiHolds = Number(max); }

                if (this.smsEnabled) {

                    return this.patron.getSmsCarriers().then(carriers => {
                        carriers.forEach(carrier => {
                            this.smsCarriers.push({
                                id: carrier.id(),
                                label: carrier.name()
                            });
                        });
                    });
                }

            }).then(_ => {

                if (this.maxMultiHolds) {

                    // Multi-copy holds are supported.  Let's see where this
                    // requestor has permission to take advantage of them.
                    return this.perm.hasWorkPermAt(
                        ['CREATE_DUPLICATE_HOLDS'], true).then(perms =>
                        this.canPlaceMultiAt = perms['CREATE_DUPLICATE_HOLDS']);
                }
            });
    }

    holdCountRange(): number[] {
        return [...Array(this.maxMultiHolds).keys()].map(n => n + 1);
    }

    // Load the bib, call number, copy, etc. data associated with each target.
    getTargetMeta(): Promise<any> {

        return new Promise(resolve => {
            this.holds.getHoldTargetMeta(this.holdType, this.holdTargets, this.auth.user().ws_ou())
                .subscribe(
                    { next: meta => {
                        this.holdContexts.filter(ctx => ctx.holdTarget === meta.target)
                            .forEach(ctx => {
                                ctx.holdMeta = meta;
                                this.mrFiltersToSelectors(ctx);
                            });
                    }, error: (err: unknown) => {}, complete: () => resolve(null) }
                );
        });
    }

    // By default, all metarecord filters options are enabled.
    mrFiltersToSelectors(ctx: HoldContext) {
        if (this.holdType !== 'M') { return; }

        const meta = ctx.holdMeta;
        if (meta.metarecord_filters) {
            if (meta.metarecord_filters.formats) {
                meta.metarecord_filters.formats.forEach(
                    ccvm => ctx.selectedFormats.formats[ccvm.code()] = true);
            }
            if (meta.metarecord_filters.langs) {
                meta.metarecord_filters.langs.forEach(
                    ccvm => ctx.selectedFormats.langs[ccvm.code()] = true);
            }
        }
    }

    // Map the selected metarecord filters optoins to a JSON-encoded
    // list of attr filters as required by the API.
    // Compiles a blob of
    // {target: JSON({"0": [{_attr: ctype, _val: code}, ...], "1": [...]})}
    // TODO: this should live in the hold service, not in the UI code.
    mrSelectorsToFilters(ctx: HoldContext): {[target: number]: string} {

        const meta = ctx.holdMeta;
        const slf = ctx.selectedFormats;
        const result: any = {};

        const formats = Object.keys(slf.formats)
            .filter(code => Boolean(slf.formats[code])); // user-selected

        const langs = Object.keys(slf.langs)
            .filter(code => Boolean(slf.langs[code])); // user-selected

        const compiled: any = {};

        if (formats.length > 0) {
            compiled['0'] = [];
            formats.forEach(code => {
                const ccvm = meta.metarecord_filters.formats.filter(
                    format => format.code() === code)[0];
                compiled['0'].push({
                    _attr: ccvm.ctype(),
                    _val: ccvm.code()
                });
            });
        }

        if (langs.length > 0) {
            compiled['1'] = [];
            langs.forEach(code => {
                const ccvm = meta.metarecord_filters.langs.filter(
                    format => format.code() === code)[0];
                compiled['1'].push({
                    _attr: ccvm.ctype(),
                    _val: ccvm.code()
                });
            });
        }

        if (Object.keys(compiled).length > 0) {
            const res = {};
            res[ctx.holdTarget] = JSON.stringify(compiled);
            return res;
        }

        return null;
    }

    holdForChanged() {
        this.user = null;

        if (this.holdFor === 'patron') {
            if (this.userBarcode) {
                this.userBarcodeChanged();
            }
        } else {
            this.userBarcode = null;
            this.currentUserBarcode = null;
            this.getUser(this.requestor.id());
        }
    }

    activeDateSelected(dateStr: string) {
        this.activeDateStr = dateStr;
    }

    setActiveDate(date: Date) {
        this.activeDate = date;
        if (date && date < new Date()) {
            this.activeDateInvalid = true;
            this.activeDateAlert.open();
        } else {
            this.activeDateInvalid = false;
        }
    }

    // Note this is called before this.userBarcode has its latest value.
    debounceUserBarcodeLookup(barcode: string | ClipboardEvent) {
        clearTimeout(this.userBarcodeTimeout);

        if (!barcode) {
            this.badBarcode = null;
            return;
        }

        const timeout =
            // eslint-disable-next-line no-magic-numbers
            (barcode && (barcode as ClipboardEvent).target) ? 0 : 500;

        this.userBarcodeTimeout =
            setTimeout(() => this.userBarcodeChanged(), timeout);
    }

    userBarcodeChanged() {
        const newBc = this.userBarcode;

        if (!newBc) { this.resetRecipient(); return; }

        // Avoid simultaneous or duplicate lookups
        if (newBc === this.currentUserBarcode) { return; }

        if (newBc !== this.staffCat.holdForBarcode) {
            // If an alternate barcode is entered, it takes us out of
            // place-hold-for-patron-x-from-search mode.
            this.staffCat.clearHoldPatron();
        }

        this.getUser();
    }

    getUser(id?: number): Promise<any> {

        let promise = this.resetForm(true);
        this.currentUserBarcode = this.userBarcode;

        const flesh = {flesh: 1, flesh_fields: {au: ['settings']}};

        promise = promise.then(_ => {
            if (id) { return id; }
            // Find the patron ID from the provided barcode.
            return this.barcodeSelect.getBarcode('actor', this.userBarcode)
                .then(selection => selection ? selection.id : null);
        });

        promise = promise.then(matchId => {
            if (matchId) {
                return this.patron.getById(matchId, flesh);
            } else {
                return null;
            }
        });

        this.badBarcode = null;
        return promise.then(user => {

            if (!user) {
                // IDs are assumed to valid
                this.badBarcode = this.userBarcode;
                return;
            }

            this.user = user;
            this.applyUserSettings();
            this.multiHoldsActive =
                this.canPlaceMultiAt.includes(user.home_ou());
            this.addRecentPatron(user.id());
        });
    }

    resetRecipient(keepBarcode?: boolean) {
        this.user = null;
        this.notifyEmail = true;
        this.notifyPhone = true;
        this.notifySms = false;
        this.phoneValue = '';
        this.pickupLib = this.requestor.ws_ou();
        this.currentUserBarcode = null;
        this.multiHoldCount = 1;
        this.smsValue = '';
        this.activeDate = null;
        this.activeDateStr = null;
        this.suspend = false;
        if (this.smsCbox) { this.smsCbox.selectedId = null; }

        // Avoid clearing the barcode in cases where the form is
        // reset as the result of a barcode change.
        if (!keepBarcode) { this.userBarcode = null; }
    }

    resetForm(keepBarcode?: boolean): Promise<any> {
        this.placeHoldsClicked = false;
        this.resetRecipient(keepBarcode);

        this.holdContexts = this.holdTargets.map(target => {
            const ctx = new HoldContext(target);
            return ctx;
        });

        // Required after rebuilding the contexts
        return this.getTargetMeta();
    }

    applyUserSettings() {
        if (!this.user) { return; }

        // Start with defaults.
        this.phoneValue = this.user.day_phone() || this.user.evening_phone();

        // Default to work org if placing holds for staff.
        // Default to home org if placing holds for patrons unless
        // settings default or fallback to the workstation.
        if (this.user.id() !== this.requestor.id()) {
            if (!this.puLibWsFallback && !this.puLibWsDefault) {
                // This value may be superseded below by user settings.
                this.pickupLib = this.user.home_ou();
            }
        }

        if (!this.user.settings()) { return; }

        this.user.settings().forEach(setting => {
            const name = setting.name();
            let value = setting.value();

            if (value === '' || value === null || value === '""') { return; }

            // When fleshing 'settings' on the actor.usr object,
            // we're grabbing the raw JSON values.
            value = JSON.parse(value);

            switch (name) {
                case 'opac.hold_notify':
                    this.notifyPhone = Boolean(value.match(/phone/));
                    this.notifyEmail = Boolean(value.match(/email/));
                    this.notifySms = Boolean(value.match(/sms/));
                    break;

                case 'opac.default_pickup_location':
                    if (!this.puLibWsDefault && value) {
                        this.pickupLib = Number(value);
                    }
                    break;

                case 'opac.default_phone':
                    this.phoneValue = value;
                    break;

                case 'opac.default_sms_carrier':
                    setTimeout(() => {
                        // timeout creates an extra window where the cbox
                        // can be rendered in cases where the hold receipient
                        // is known at page load time.  This out of an
                        // abundance of caution.
                        if (this.smsCbox) {
                            this.smsCbox.selectedId = Number(value);
                        }
                    });
                    break;

                case 'opac.default_sms_notify':
                    this.smsValue = value;
                    break;
            }
        });

        if (!this.user.email()) {
            this.notifyEmail = false;
        }

        if (!this.phoneValue) {
            this.notifyPhone = false;
        }
    }

    readyToPlaceHolds(): boolean {
        if (!this.user || this.placeHoldsClicked || this.activeDateInvalid) {
            return false;
        }
        if (!this.pickupLib || this.disableOrgs.includes(this.pickupLib)) {
            return false;
        }
        if (this.smsEnabled && this.notifySms) {
            if (!this.smsValue.length || !this.smsCbox?.selectedId) {
                return false;
            }
        }
        return true;
    }

    // Attempt hold placement on all targets
    placeHolds(idx?: number, override?: boolean) {
        if (!idx) {
            idx = 0;
            if (this.multiHoldCount > 1 && !override) {
                this.addMultHoldContexts();
            }
        }

        if (!this.holdContexts[idx]) {
            return this.afterPlaceHolds(idx > 0);
        }

        this.placeHoldsClicked = true;

        const ctx = this.holdContexts[idx];
        this.placeOneHold(ctx, override).then(() =>
            this.placeHolds(idx + 1, override)
        );
    }

    afterPlaceHolds(somePlaced: boolean) {
        this.placeHoldsClicked = false;

        if (!somePlaced) { return; }

        // At least one hold attempted.  Confirm all succeeded
        // before resetting the recipient info in the form.
        let reset = true;
        this.holdContexts.forEach(ctx => {
            if (!ctx.success) { reset = false; }
        });

        if (reset) { this.resetRecipient(); }
    }

    // When placing holds on multiple copies per target, add a hold
    // context for each instance of the request.
    addMultHoldContexts() {
        const newContexts = [];

        this.holdContexts.forEach(ctx => {
            for (let idx = 2; idx <= this.multiHoldCount; idx++) {
                const newCtx = ctx.clone(ctx.holdTarget);
                newContexts.push(newCtx);
            }
        });

        // Group the contexts by hold target
        this.holdContexts = this.holdContexts.concat(newContexts)
            .sort((h1, h2) =>
                h1.holdTarget === h2.holdTarget ? 0 :
                    h1.holdTarget < h2.holdTarget ? -1 : 1
            );
    }

    placeOneHold(ctx: HoldContext, override?: boolean): Promise<any> {

        if (override && !this.canOverride(ctx)) {
            return Promise.resolve();
        }

        ctx.processing = true;
        const selectedFormats = this.mrSelectorsToFilters(ctx);

        let hType = this.holdType;
        let hTarget = ctx.holdTarget;

        if (ctx.holdMeta.parts && !ctx.holdMeta.part) {
            ctx.holdMeta.part = (ctx.holdMeta.part_required ? ctx.holdMeta.parts[0] : null);
        }

        if (hType === 'T' && ctx.holdMeta.part) {
            // A Title hold morphs into a Part hold at hold placement time
            // if a part is selected.  This can happen on a per-hold basis
            // when placing T-level holds.
            hType = 'P';
            hTarget = ctx.holdMeta.part.id();
        }

        console.debug(`Placing ${hType}-type hold on ${hTarget}`);

        return this.holds.placeHold({
            holdTarget: hTarget,
            holdType: hType,
            recipient: this.user.id(),
            requestor: this.requestor.id(),
            pickupLib: this.pickupLib,
            override: override,
            notifyEmail: this.notifyEmail, // bool
            notifyPhone: this.notifyPhone ? this.phoneValue : null,
            notifySms: this.smsEnabled && this.notifySms ? this.smsValue : null,
            smsCarrier: this.smsCbox ? this.smsCbox.selectedId : null,
            thawDate: this.suspend ? this.activeDateStr : null,
            frozen: this.suspend,
            holdableFormats: selectedFormats

        }).toPromise().then(
            request => {
                ctx.lastRequest = request;
                ctx.processing = false;

                if (request.result.success) {
                    ctx.success = true;

                    this.worklog.record({
                        action: 'requested_hold',
                        hold_id: request.result.holdId,
                        patron_id: this.user.id(),
                        user: this.user.family_name()
                    });

                } else {
                    console.debug('hold failed with: ', request);

                    // If this request failed and was not already an override,
                    // see of this user has permission to override.
                    if (!request.override && request.result.evt) {

                        const txtcode = request.result.evt.textcode;
                        const perm = txtcode + '.override';

                        return this.perm.hasWorkPermHere(perm).then(
                            permResult => ctx.canOverride = permResult[perm]);
                    }
                }
            },
            error => {
                ctx.processing = false;
                console.error(error);
            }
        );
    }

    override(ctx: HoldContext) {
        this.placeOneHold(ctx, true).then(() => {
            this.afterPlaceHolds(ctx.success);
        });
    }

    canOverride(ctx: HoldContext): boolean {
        return ctx.lastRequest &&
                !ctx.lastRequest.result.success && ctx.canOverride;
    }

    showOverrideAll(): boolean {
        return this.holdContexts.filter(ctx =>
            this.canOverride(ctx)
        ).length > 1;
    }

    overrideAll(): void {
        this.placeHolds(0, true);
    }

    iconFormatLabel(code: string): string {
        return this.cat.iconFormatLabel(code);
    }

    // TODO: for now, only show meta filters for meta holds.
    // Add an "advanced holds" option to display these for T hold.
    hasMetaFilters(ctx: HoldContext): boolean {
        return (
            this.holdType === 'M' && // TODO
            ctx.holdMeta.metarecord_filters && (
                ctx.holdMeta.metarecord_filters.langs.length > 1 ||
                ctx.holdMeta.metarecord_filters.formats.length > 1
            )
        );
    }

    triggerPatronChange(user?: IdlObject): void {
        if (user) {
            this.userBarcode = user.card().barcode();
            this.userBarcodeChanged();
        }
    }

    searchPatrons(idsToAutoLoad?: number[]): void {
        this.patronSearch.patronIds = idsToAutoLoad;
        firstValueFrom(this.patronSearch.open({size: 'xl'}))
            .then(patrons => this.triggerPatronChange(patrons?.[0]));
    }

    searchRecentPatrons(): void {
        this.refreshRecentPatronIds();

        if (this.recentPatronIds.length === 1) {
            // load recent patron
            this.patron.getFleshedById(this.recentPatronIds[0])
                .then(patron => this.triggerPatronChange(patron));
        } else {
            // initialize search dialog with recent patrons
            this.searchPatrons(this.recentPatronIds);
        }
    }

    initRecentPatrons(enabled: boolean, max: number): void {
        if (enabled && max > 0) {
            this.maxRecentPatrons = max;
            this.refreshRecentPatronIds();

            // Sync recent patrons across tabs on window focus
            // instead of on every change detection.
            window.addEventListener('focus', this.refreshRecentPatronIds);
        }
    }

    getRecentPatronIds(): number[] {
        const key = 'eg.circ.recent_patrons';
        const ids = this.sessionStore.getLoginSessionItem(key) || [];
        return ids.slice(0, this.maxRecentPatrons);
    }

    refreshRecentPatronIds = (): void => {
        this.recentPatronIds = this.getRecentPatronIds();
    };

    addRecentPatron(id: number): void {
        if (!this.maxRecentPatrons || !id) { return; }

        const recentIds = this.getRecentPatronIds();
        if (recentIds?.[0] === id) { return; }

        this.recentPatronIds = [
            id,
            ...recentIds.filter(recentId => recentId !== id)
        ].slice(0, this.maxRecentPatrons);

        const key = 'eg.circ.recent_patrons';
        this.sessionStore.setLoginSessionItem(key, this.recentPatronIds);
    }

    recentPatronsDisabled(): boolean {
        return this.recentPatronIds.length === 1
            ? this.recentPatronIds[0] === this.user?.id()
            : !this.recentPatronIds.length;
    }

    isItemHold(): boolean {
        return this.holdType === 'C'
            || this.holdType === 'R'
            || this.holdType === 'F';
    }

    setPart(ctx: HoldContext, $event) {
        const partId = $event.target.value;
        if (partId) {
            ctx.holdMeta.part =
                ctx.holdMeta.parts.filter(p => +p.id() === +partId)[0];
        } else {
            ctx.holdMeta.part = null;
        }
    }

    hasNoHistory(): boolean {
        return history.length === 0;
    }

    goBack() {
        history.back();
    }

    ngOnDestroy(): void {
        if (this.maxRecentPatrons) {
            window.removeEventListener('focus', this.refreshRecentPatronIds);
        }
    }
}


