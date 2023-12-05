import { AuthService } from '@eg/core/auth.service';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { Observable, of } from 'rxjs';

// Convenience functions that generate mock data for tests
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
}
