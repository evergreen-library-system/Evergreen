import { AuthService } from '@eg/core/auth.service';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { LocaleService } from '@eg/core/locale.service';
import { NetService } from '@eg/core/net.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { PermService } from '@eg/core/perm.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { StoreService } from '@eg/core/store.service';
import { CatalogSearchContext } from '@eg/share/catalog/search-context';
import { ItemLocationService } from '@eg/share/item-location-select/item-location.service';
import { BatchLineitemStruct, FleshCacheParams, LineitemService } from '@eg/staff/acq/lineitem/lineitem.service';
import { StaffCatalogService } from '@eg/staff/catalog/catalog.service';
import { SerialsService } from '@eg/staff/serials/serials.service';
import { HoldsService } from '@eg/staff/share/holds/holds.service';
import { PatronService } from '@eg/staff/share/patron/patron.service';
import { EMPTY, from, Observable, of } from 'rxjs';

// Convenience functions that generate mock data for use in automated tests
export class MockGenerators {
    static idlObject(keysAndValues: {[key: string]: any}, classname?, isFieldMapper?): IdlObject {
        const object = {
            a: null,
            _isfieldmapper: isFieldMapper,
            classname: classname,
            originalValues: keysAndValues,
            changedValues: {}
        };
        Object.keys(keysAndValues).forEach((key) => {
            object[key] = (newValue?: any) => {
                if (newValue !== undefined) {
                    object.changedValues[key] = newValue;
                } else {
                    // Note: we can't do object.changedValues[key] ?? object.originalValues[key],
                    // since the value of the field could be null
                    return key in object.changedValues ? object.changedValues[key] : object.originalValues[key];
                }
            };
        });
        return object;
    }

    static authService() {
        const user = MockGenerators.idlObject({ws_ou: 10});
        const auth = jasmine.createSpyObj<AuthService>(['user', 'token']);
        auth.user.and.returnValue(user);
        auth.token.and.returnValue('MY_AUTH_TOKEN');
        return auth;
    }

    static holdsService() {
        const service = jasmine.createSpyObj<HoldsService>(['getHoldTargetMeta', 'placeHold']);
        service.placeHold.and.returnValue(of({
            holdType: 'B',
            holdTarget: 1,
            recipient: 2,
            requestor: 3,
            pickupLib: 4,
            result: { success: true, holdId: 303 }
        }));
        service.getHoldTargetMeta.and.returnValue(EMPTY);
        return service;
    }

    static idlService(classes: {}) {
        const service = jasmine.createSpyObj<IdlService>(
            ['getClassSelector', 'create', 'pkeyMatches', 'sortIdlFields'],
            {classes: classes}
        );
        service.create.and.callFake((cls: string, seed?: any) => {
            return new Proxy({
                a: [],
                classname: cls,
                _isfieldmapper: true
            }, {
                get(target, property, receiver) {
                    if (['a', 'classname', '_isfieldmapper'].includes(property as string)) {
                        return target[property];
                    } else {
                        return (value) => null;
                    }
                }
            });
        });
        service.sortIdlFields.and.callFake((fields, _desiredOrder) => fields);
        return service;
    }

    static itemLocationService(): ItemLocationService {
        return {
            getById: (_id: number) => of(this.idlObject({owning_lib: 4, name: 'Romance fiction'}))
        } as ItemLocationService;
    }

    static lineItemService(): LineitemService {
        return {
            getFleshedLineitems: (_ids: number[], _params?: FleshCacheParams): Observable<BatchLineitemStruct> => EMPTY
        } as LineitemService;
    }

    static localeService(returnValues = {}): Partial<LocaleService> {
        return {
            currentLocaleCode: () => returnValues['currentLocaleCode'] || 'en-US',
            setLocale: (code: string) => {},
            supportedLocaleCodes: () => returnValues['supportedLocaleCodes'] || ['en-US'],
            supportedLocales: () => of(returnValues['supportedLocales'] || MockGenerators.idlObject({code: 'en-US'})),
        } as Partial<LocaleService>;
    }

    // Use the method response map to say which OpenSRF methods
    // you expect to call, and what the response should be.
    // For example:
    // {'opensrf.math.add', of(4)}
    static netService(method_response_map: {}) {
        const net = jasmine.createSpyObj<NetService>(['request']);
        net.request.and.callFake((_service, method, _params) => {
            if (method_response_map[method]) {
                return method_response_map[method];
            }
            return of(`OpenSRF method ${method} has not been mocked, returning this string instead`);
        });
        return net;
    }

    // Create a mock patron
    static patron(properties={}) {
        const defaults = {
            active: true,
            addresses: [],
            barred: false,
            card: {barcode: () => '12345'},
            create_date: new Date(),
            day_phone: '111-555-2222',
            email: 'me@example.com',
            evening_phone: '111-555-2222',
            expire_date: new Date(),
            guardian: 'My guardian',
            guardian_email: 'my@guardian.org',
            home_ou: 'My Library',
            ident_value: null,
            ident_value2: null,
            juvenile: false,
            last_update_time: new Date(),
            net_access_level: {name: () => 'Unfiltered'},
            name_keywords: [],
            notes: [],
            other_phone: '111-555-2222',
            profile: {name: () => 'Patrons'},
            standing_penalties: [],
            usr_activity: [MockGenerators.idlObject({event_time: new Date()})],
            usrname: 'hello123',
            waiver_entries: [],
        };
        return this.idlObject({...defaults, ...properties});
    }

    static patronService() {
        const patron = jasmine.createSpyObj<PatronService>(['getById', 'namePart']);
        patron.getById.and.resolveTo(this.idlObject({id: 1, day_phone: '555-1234', settings: [], email: null, home_ou: 1}));
        patron.namePart.and.returnValue('Your Best Friend');
        return patron;
    }

    static permService(permissions_result: {}) {
        const perm = jasmine.createSpyObj<PermService>(['hasWorkPermHere']);
        perm.hasWorkPermHere.and.resolveTo(permissions_result);
        return perm;
    }

    static pcrudService(returnValues: {[method: string]: any[]}) {
        const methods = ['search', 'retrieve', 'retrieveAll', 'create', 'update', 'remove'];
        const pcrud = jasmine.createSpyObj<PcrudService>(['search', 'retrieve', 'retrieveAll', 'create', 'update', 'remove']);
        methods.forEach((method) => {
            pcrud[method].and.returnValue(from(returnValues[method] || []));
        });
        return pcrud;
    }

    static storeService(valueFromStore: any) {
        const store = jasmine.createSpyObj<StoreService>(['getLocalItem', 'setLocalItem', 'getLoginSessionItem']);
        store.getLocalItem.and.returnValue(valueFromStore);
        return store;
    }

    static serverStoreService(valueFromStore: any) {
        const store = jasmine.createSpyObj<ServerStoreService>(['getItem']);
        store.getItem.and.resolveTo(valueFromStore);
        return store;
    }

    static serialsService() {
        const methods = [
            'callNumberPrefixesAsComboboxEntries$', 'callNumbersAsComboboxEntries$', 'callNumberSuffixesAsComboboxEntries$',
            'defaultCallNumber$', 'defaultCallNumberPrefix$', 'defaultCallNumberSuffix$', 'shouldShowCallNumberAffixes',
            'storeCallNumberAffixPreference'
        ];
        const serials = jasmine.createSpyObj<SerialsService>(methods as (keyof SerialsService)[]);
        methods.forEach(method => {
            // Methods in this service that return an observable are indicated with the $ suffix
            if (method.slice(-1) === '$') {
                serials[method].and.returnValue(of());
            }
        });
        return serials;
    }

    static staffCatService(context: CatalogSearchContext) {
        return jasmine.createSpyObj<StaffCatalogService>([], {
            searchContext: context
        });
    }

    static orgService() {
        return {
            ancestors: () => [],
            get: (nodeOrOrgId: any) => this.idlObject({shortname: 'MYLIB'}),
            list: () => of([]),
            settings: () => Promise.resolve(null),
        };
    }
}

interface BasicGlobalFlag {
    name: string;
    enabled: boolean;
    label?: string;
    value?: string;
}
