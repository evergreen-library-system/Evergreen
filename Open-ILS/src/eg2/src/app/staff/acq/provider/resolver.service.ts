import {Injectable} from '@angular/core';
import {Observable} from 'rxjs';
import {Router, Resolve, RouterStateSnapshot,
        ActivatedRouteSnapshot, CanDeactivate} from '@angular/router';
import {ProviderRecordService} from './provider-record.service';

@Injectable()
export class ProviderResolver implements Resolve<Promise<any[]>> {

    savedId: number = null;

    constructor(
        private router: Router,
        private providerRecord: ProviderRecordService,
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        console.debug('ProviderResolver:resolve()');

        const id = Number(route.paramMap.get('id'));

        if (this.savedId !== null && this.savedId === id) {
            // don't refetch
            return Promise.all([
                Promise.resolve(),
            ]);
        } else {
            this.savedId = id;
            return Promise.all([
                this.providerRecord.fetch(id).then(
                    ok => {
                        console.debug(this.providerRecord.current());
                    },
                    err => {
                        this.router.navigate(['/staff', 'acq', 'provider']);
                    }
                ),
            ]);
        }
    }

}

// following example of https://www.concretepage.com/angular-2/angular-candeactivate-guard-example
export interface DeactivationGuarded {
    canDeactivate(): Observable<boolean> | Promise<boolean> | boolean;
}

@Injectable()
export class CanLeaveAcqProviderGuard implements CanDeactivate<DeactivationGuarded> {
    canDeactivate(component: DeactivationGuarded):  Observable<boolean> | Promise<boolean> | boolean {
        return component.canDeactivate ? component.canDeactivate() : true;
    }
}
