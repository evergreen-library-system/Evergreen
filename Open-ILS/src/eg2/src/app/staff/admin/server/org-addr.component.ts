import {Component, Input, Output, EventEmitter} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {ToastService} from '@eg/share/toast/toast.service';

const ADDR_TYPES =
    ['billing_address', 'holds_address', 'mailing_address', 'ill_address'];

@Component({
    selector: 'eg-admin-org-address',
    templateUrl: './org-addr.component.html'
})
export class OrgAddressComponent {

    orgUnit: IdlObject = null;
    tabName: string;

    private _orgId: number;

    get orgId(): number { return this._orgId; }

    @Input() set orgId(newId: number) {
        if (newId) {
            if (!this._orgId || this._orgId !== newId) {
                this._orgId = newId;
                this.init();
            }
        } else {
            this._orgId = null;
        }
    }

    @Output() addrChange: EventEmitter<IdlObject>;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private net: NetService,
        private toast: ToastService
    ) {
        this.addrChange = new EventEmitter<IdlObject>();
    }

    init() {
        if (!this.orgId) { return; }

        this.tabName = 'billing_address';

        return this.pcrud.retrieve('aou', this.orgId,
            {flesh : 1, flesh_fields : {aou : ADDR_TYPES}},
            {authoritative: true}
        ).subscribe(org => {
            this.orgUnit = org;
            ADDR_TYPES.forEach(aType => {
                if (!this.addr(aType)) {
                    this.createAddress(aType);
                }
            });
        });
    }

    addrTypes(): string[] { // for UI
        return ADDR_TYPES;
    }

    // Template shorthand -- get a specific address by type.
    addr(addrType: string) {
        return this.orgUnit ? this.orgUnit[addrType]() : null;
    }

    createAddress(addrType: string) {
        const addr = this.idl.create('aoa');
        addr.isnew(true);
        addr.valid('t');
        addr.org_unit(this.orgId);
        this.orgUnit[addrType](addr);
    }

    cloneAddress(addrType: string) {

        // Find the address
        let fromAddr: IdlObject;
        ADDR_TYPES.forEach(aType => {
            if (aType !== addrType &&
                this.addr(aType).id() === this.addr(addrType).id()) {
                fromAddr = this.addr(aType);
            }
        });

        const addr = this.idl.clone(fromAddr);
        addr.id(null);
        addr.isnew(true);
        addr.valid('t');
        this.orgUnit[addrType](addr);
    }

    // True if the provided address is used for more than one addr type.
    sharedAddress(addrId: number): boolean {
        return ADDR_TYPES.filter(aType => {
            return (
                !this.addr(aType).isnew() && this.addr(aType).id() === addrId
            );
        }).length > 1;
    }

    deleteAddress($event: any) {
        const addr = $event.record;
        const tmpOrg = this.updatableOrg();

        // Set the FKey to NULL on the org unit for deleted addresses
        ADDR_TYPES.forEach(aType => {
            const a = this.addr(aType);
            if (a && a.id() === addr.id()) {
                tmpOrg[aType](null);
                this.createAddress(aType);
            }
        });

        this.pcrud.update(tmpOrg).toPromise()
            .then(_ => this.pcrud.remove(addr).toPromise())
            .then(_ => this.addrChange.emit(addr));
    }

    // Addr saved by fm-editor.
    // In the case of new address creation, point the org unit at
    // the new address ID.
    addrSaved(addr: number | IdlObject) {

        if (typeof addr !== 'object') {
            // pcrud returns a number on 'update' calls.  No need to
            // reload the data on a simple address change. it's changed
            // in place.
            return;
        }

        // update local copy with version that has an ID.
        this.orgUnit[this.tabName](addr);

        const org = this.updatableOrg();
        org[this.tabName](addr.id());

        // Creating a new address -- tell our org about it.
        this.pcrud.update(org).toPromise().then(_ => this.addrChange.emit(addr));
    }

    // Create an unfleshed org unit object that's a clone of this.orgUnit
    // to use when pushing updates to the server.
    updatableOrg(): IdlObject {
        const org = this.idl.clone(this.orgUnit);

        ADDR_TYPES.forEach(aType => {
            const addr = this.addr(aType);
            if (addr) { org[aType](addr.id()); }
        });

        return org;
    }

    getCoordinates($event: any) {
        const addr = $event.record;
        this.net.request(
            'open-ils.actor',
            'open-ils.actor.geo.retrieve_coordinates',
            this.auth.token(),
            typeof addr.org_unit() === 'object' ? addr.org_unit().id() : addr.org_unit(),
            addr.street1() + ' ' + addr.street2() + ', '
            + addr.city() + ', ' + addr.state() + ' ' + addr.post_code()
            + ' ' + addr.country()
        ).subscribe(
            { next: (res) => {
                console.log('geo', res);
                if (typeof res.ilsevent === 'undefined') {
                    addr.latitude( res.latitude );
                    addr.longitude( res.longitude );
                } else {
                    this.toast.danger(res.desc);
                }
            }, error: (err: unknown) => {
                console.error('geo', err);
            } }
        );
    }
}

