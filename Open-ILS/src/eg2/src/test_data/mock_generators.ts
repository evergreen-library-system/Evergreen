import { AuthService } from '@eg/core/auth.service';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { NetService } from '@eg/core/net.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { PermService } from '@eg/core/perm.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { StoreService } from '@eg/core/store.service';
import { CatalogSearchContext } from '@eg/share/catalog/search-context';
import { StaffCatalogService } from '@eg/staff/catalog/catalog.service';
import { SerialsService } from '@eg/staff/serials/serials.service';
import { of } from 'rxjs';

// Convenience functions that generate mock data for use in automated tests
export class MockGenerators {
    static idlObject(keysAndValues: {[key: string]: any}) {
        const object = jasmine.createSpyObj<IdlObject>(Object.keys(keysAndValues));
        Object.keys(keysAndValues).forEach((key) => {
            object[key].and.returnValue(keysAndValues[key]);
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

    static idlService(classes: {}) {
        return jasmine.createSpyObj<IdlService>(['getClassSelector'], {classes: classes});
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

    static permService(permissions_result: {}) {
        const perm = jasmine.createSpyObj<PermService>(['hasWorkPermHere']);
        perm.hasWorkPermHere.and.resolveTo(permissions_result);
        return perm;
    }

    static pcrudService(returnValues: {[method: string]: any}) {
        const methods = ['search', 'retrieve', 'retrieveAll', 'create', 'update', 'remove'];
        const pcrud = jasmine.createSpyObj<PcrudService>(['search', 'retrieve', 'retrieveAll', 'create', 'update', 'remove']);
        methods.forEach((method) => {
            if (returnValues[method]) {
                pcrud[method].and.returnValue(of(returnValues[method]));
            } else {
                pcrud[method].and.returnValue(of());
            }
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
        return {ancestors: () => []};
    }
}
