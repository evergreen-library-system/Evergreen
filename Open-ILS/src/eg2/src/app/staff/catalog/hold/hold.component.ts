import {Component, OnInit, Input, ViewChild, Renderer2} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {PermService} from '@eg/core/perm.service';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {StaffCatalogService} from '../catalog.service';
import {HoldsService, HoldRequest,
    HoldRequestTarget} from '@eg/staff/share/holds/holds.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {PatronSearchDialogComponent
  } from '@eg/staff/share/patron/search-dialog.component';

class HoldContext {
    holdMeta: HoldRequestTarget;
    holdTarget: number;
    lastRequest: HoldRequest;
    canOverride?: boolean;
    processing: boolean;
    selectedFormats: any;

    constructor(target: number) {
        this.holdTarget = target;
        this.processing = false;
        this.selectedFormats = {
           // code => selected-boolean
           formats: {},
           langs: {}
        };
    }
}

@Component({
  templateUrl: 'hold.component.html'
})
export class HoldComponent implements OnInit {

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
    smsCarrier: string;
    suspend: boolean;
    activeDate: string;

    holdContexts: HoldContext[];
    recordSummaries: BibRecordSummary[];

    currentUserBarcode: string;
    smsCarriers: ComboboxEntry[];

    smsEnabled: boolean;
    placeHoldsClicked: boolean;

    @ViewChild('patronSearch', {static: false})
      patronSearch: PatronSearchDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private renderer: Renderer2,
        private evt: EventService,
        private net: NetService,
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private bib: BibRecordService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService,
        private holds: HoldsService,
        private perm: PermService
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

        if (!Array.isArray(this.holdTargets)) {
            this.holdTargets = [this.holdTargets];
        }

        this.holdTargets = this.holdTargets.map(t => Number(t));

        this.requestor = this.auth.user();
        this.pickupLib = this.auth.user().ws_ou();

        this.holdContexts = this.holdTargets.map(target => {
            const ctx = new HoldContext(target);
            return ctx;
        });

        if (this.holdFor === 'staff') {
            this.holdForChanged();
        }

        this.getTargetMeta();

        this.org.settings('sms.enable').then(sets => {
            this.smsEnabled = sets['sms.enable'];
            if (!this.smsEnabled) { return; }

            this.pcrud.search('csc', {active: 't'}, {order_by: {csc: 'name'}})
            .subscribe(carrier => {
                this.smsCarriers.push({
                    id: carrier.id(),
                    label: carrier.name()
                });
            });
        });

        setTimeout(() => // Focus barcode input
            this.renderer.selectRootElement('#patron-barcode').focus());
    }

    // Load the bib, call number, copy, etc. data associated with each target.
    getTargetMeta() {
        this.holds.getHoldTargetMeta(this.holdType, this.holdTargets)
        .subscribe(meta => {
            this.holdContexts.filter(ctx => ctx.holdTarget === meta.target)
            .forEach(ctx => {
                ctx.holdMeta = meta;
                this.mrFiltersToSelectors(ctx);
            });
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
            // To bypass the dupe check.
            this.currentUserBarcode = '_' + this.requestor.id();
            this.getUser(this.requestor.id());
        }
    }

    activeDateSelected(dateStr: string) {
        this.activeDate = dateStr;
    }

    userBarcodeChanged() {

        // Avoid simultaneous or duplicate lookups
        if (this.userBarcode === this.currentUserBarcode) {
            return;
        }

        this.resetForm();

        if (!this.userBarcode) {
            this.user = null;
            return;
        }

        this.user = null;
        this.currentUserBarcode = this.userBarcode;

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            this.auth.token(), this.auth.user().ws_ou(),
            'actor', this.userBarcode
        ).subscribe(barcodes => {

            // Use the first successful barcode response.
            // TODO: What happens when there are multiple responses?
            // Use for-loop for early exit since we have async
            // action within the loop.
            for (let i = 0; i < barcodes.length; i++) {
                const bc = barcodes[i];
                if (!this.evt.parse(bc)) {
                    this.getUser(bc.id);
                    break;
                }
            }
        });
    }

    resetForm() {
        this.notifyEmail = true;
        this.notifyPhone = true;
        this.phoneValue = '';
        this.pickupLib = this.requestor.ws_ou();
    }

    getUser(id: number) {
        this.pcrud.retrieve('au', id, {flesh: 1, flesh_fields: {au: ['settings']}})
        .subscribe(user => {
            this.user = user;
            this.applyUserSettings();
        });
    }

    applyUserSettings() {
        if (!this.user || !this.user.settings()) { return; }

        // Start with defaults.
        this.phoneValue = this.user.day_phone() || this.user.evening_phone();

        // Default to work org if placing holds for staff.
        if (this.user.id() !== this.requestor.id()) {
            this.pickupLib = this.user.home_ou();
        }

        this.user.settings().forEach(setting => {
            const name = setting.name();
            const value = setting.value();

            if (value === '' || value === null) { return; }

            switch (name) {
                case 'opac.hold_notify':
                    this.notifyPhone = Boolean(value.match(/phone/));
                    this.notifyEmail = Boolean(value.match(/email/));
                    this.notifySms = Boolean(value.match(/sms/));
                    break;

                case 'opac.default_pickup_location':
                    this.pickupLib = value;
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

    // Attempt hold placement on all targets
    placeHolds(idx?: number) {
        if (!idx) { idx = 0; }
        if (!this.holdTargets[idx]) {
            this.placeHoldsClicked = false;
            return;
        }
        this.placeHoldsClicked = true;

        const target = this.holdTargets[idx];
        const ctx = this.holdContexts.filter(
            c => c.holdTarget === target)[0];

        this.placeOneHold(ctx).then(() => this.placeHolds(idx + 1));
    }

    placeOneHold(ctx: HoldContext, override?: boolean): Promise<any> {

        ctx.processing = true;
        const selectedFormats = this.mrSelectorsToFilters(ctx);

        let hType = this.holdType;
        let hTarget = ctx.holdTarget;
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
            notifySms: this.notifySms ? this.smsValue : null,
            smsCarrier: this.notifySms ? this.smsCarrier : null,
            thawDate: this.suspend ? this.activeDate : null,
            frozen: this.suspend,
            holdableFormats: selectedFormats

        }).toPromise().then(
            request => {
                ctx.lastRequest = request;
                ctx.processing = false;

                if (!request.result.success) {
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
        this.placeOneHold(ctx, true);
    }

    canOverride(ctx: HoldContext): boolean {
        return ctx.lastRequest &&
                !ctx.lastRequest.result.success && ctx.canOverride;
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

    searchPatrons() {
        this.patronSearch.open({size: 'xl'}).toPromise().then(
            patrons => {
                if (!patrons || patrons.length === 0) { return; }

                const user = patrons[0];

                this.user = user;
                this.userBarcode =
                    this.currentUserBarcode = user.card().barcode();
                user.home_ou(this.org.get(user.home_ou()).id()); // de-flesh
                this.applyUserSettings();
            }
        );
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
}


