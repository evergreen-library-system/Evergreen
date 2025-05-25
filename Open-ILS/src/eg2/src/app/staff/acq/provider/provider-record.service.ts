import {Injectable} from '@angular/core';
import {Observable, Subject, map, defaultIfEmpty} from 'rxjs';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PermService} from '@eg/core/perm.service';

export class ProviderSummary {
}

export class ProviderRecord {
    id: number;
    record: IdlObject;
    canDelete: boolean;
    canAdmin: boolean;

    constructor(record: IdlObject) {
        this.id = Number(record.id());
        this.record = record;
        this.canDelete = false;
        this.canAdmin = false;
    }
}

@Injectable()
export class ProviderRecordService {

    public currentProvider: ProviderRecord;
    private currentProviderId: number = null;

    private providerUpdatedSource = new Subject<number>();
    providerUpdated$ = this.providerUpdatedSource.asObservable();

    private permissions: any;
    private viewOUs: number[] = [];

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        private perm: PermService
    ) {
        this.currentProvider = null;
        this.loadPerms();
    }

    loadPerms(): Promise<any> {
        if (this.permissions) {
            return Promise.resolve();
        }
        return this.perm.hasWorkPermAt(['ADMIN_PROVIDER', 'MANAGE_PROVIDER', 'VIEW_PROVIDER'], true).then(permMap => {
            this.permissions = permMap;
            this.viewOUs.concat(permMap['VIEW_PROVIDER']);
            this.permissions['ADMIN_PROVIDER'].forEach(ou => {
                if (!this.viewOUs.includes(ou)) {
                    this.viewOUs.push(ou);
                }
            });
            this.permissions['MANAGE_PROVIDER'].forEach(ou => {
                if (!this.viewOUs.includes(ou)) {
                    this.viewOUs.push(ou);
                }
            });
        });
    }

    getProviderRecord(id: number): Observable<ProviderRecord> {
        console.debug('fetching provider ' + id);
        this.currentProviderId = id;
        const emptyGuard = this.idl.create('acqpro');
        emptyGuard.id('no_provider_fetched');
        return this.pcrud.search('acqpro', { id: id },
            {
                flesh: 3,
                flesh_fields: { acqpro:   [
                    'attributes', 'holdings_subfields', 'contacts',
                    'addresses', 'provider_notes',
                    'edi_accounts', 'currency_type', 'edi_default'
                ],
                acqpa:    ['provider'],
                acqpc:    ['provider', 'addresses'],
                acqphsm:  ['provider'],
                acqlipad: ['provider'],
                acqedi:   ['attr_set', 'provider'],
                }
            },
            {}
        ).pipe(defaultIfEmpty(emptyGuard), map(acqpro => {
            if (acqpro.id() === 'no_provider_fetched') {
                throw new Error('no provider to fetch');
            }
            const provider = new ProviderRecord(acqpro);
            // make a copy of holding_tag for use by the holdings definitions tab
            acqpro['_holding_tag'] = acqpro.holding_tag();
            acqpro.edi_accounts().forEach(acct => {
                acct['_is_default'] = false;
                if (acqpro.edi_default()) {
                    if (acct.id() === acqpro.edi_default().id()) {
                        acct['_is_default'] = true;
                    }
                }
            });
            acqpro.contacts().forEach(acct => {
                acct['_is_primary'] = false;
                if (acqpro.primary_contact()) {
                    if (acct.id() === acqpro.primary_contact()) {
                        acct['_is_primary'] = true;
                    }
                }
            });
            this.currentProvider = provider;
            this.checkIfCanDelete(provider);
            this.checkIfCanAdmin(provider);
            return provider;
        }));
    }

    checkIfCanDelete(prov: ProviderRecord) {
        this.pcrud.search('acqpo', { provider: prov.id }, { limit: 1 }).toPromise()
            .then(acqpo => {
                if (!acqpo || acqpo.length === 0) {
                    this.pcrud.search('jub', { provider: prov.id }, { limit: 1 }).toPromise()
                        .then(jub => {
                            if (!jub || jub.length === 0) {
                                this.pcrud.search('acqinv', { provider: prov.id }, { limit: 1 }).toPromise()
                                    .then(acqinv => {
                                        prov.canDelete = true;
                                    });
                            }
                        });
                }
            });
    }

    checkIfCanAdmin(prov: ProviderRecord) {
        this.loadPerms().then(x => {
            if (Object.keys(this.permissions).length > 0 &&
                this.permissions['ADMIN_PROVIDER'].includes(prov.record.owner())) {
                prov.canAdmin = true;
            }
        });
    }

    checkIfCanAdminAtAll(): boolean {
        if (typeof this.permissions === 'undefined') {
            return false;
        }
        if (Object.keys(this.permissions).length > 0 &&
            this.permissions['ADMIN_PROVIDER'].length > 0) {
            return true;
        } else {
            return false;
        }
    }

    getViewOUs(): number[] {
        return this.viewOUs;
    }

    current(): IdlObject {
        return this.currentProvider ? this.currentProvider.record : null;
    }
    currentProviderRecord(): ProviderRecord {
        return this.currentProvider ? this.currentProvider : null;
    }

    fetch(id: number): Promise<void> {
        return new Promise((resolve, reject) => {
            this.getProviderRecord(id).subscribe(
                { next: result => {
                    resolve();
                }, error: (error: unknown) => {
                    reject();
                } },
            );
        });
    }

    refreshCurrent(): Promise<any> {
        if (this.currentProviderId) {
            return this.fetch(this.currentProviderId);
        } else {
            return Promise.reject();
        }
    }

    batchUpdate(list: IdlObject | IdlObject[]): Observable<any> {
        return this.pcrud.autoApply(list);
    }

    announceProviderUpdated() {
        this.providerUpdatedSource.next(this.currentProviderId);
    }

}
