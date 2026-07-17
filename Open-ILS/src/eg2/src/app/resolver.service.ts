import { Injectable, inject } from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
    ActivatedRouteSnapshot} from '@angular/router';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {LocaleService} from '@eg/core/locale.service';
import {PcrudService} from '@eg/core/pcrud.service';

// For locale application
declare let OpenSRF;

@Injectable()
export class BaseResolver implements Resolve<Promise<void>> {
    private router = inject(Router);
    private idl = inject(IdlService);
    private org = inject(OrgService);
    private pcrud = inject(PcrudService);
    private locale = inject(LocaleService);


    /**
     * Loads pre-auth data common to all applications.
     * No auth token is available at this level.  When needed, auth is
     * enforced by application/group-specific resolvers at lower levels.
     */
    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<void> {

        OpenSRF.locale = this.locale.currentLocaleCode();

        this.idl.parseIdl();
        this.pcrud.setAuthoritative();

        return this.org.fetchOrgs();
    }
}
