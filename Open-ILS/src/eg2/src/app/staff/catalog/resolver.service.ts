import {Injectable} from '@angular/core';
import {Observable, Observer} from 'rxjs';
import {Router, Resolve, RouterStateSnapshot,
        ActivatedRouteSnapshot} from '@angular/router';
import {ServerStoreService} from '@eg/core/server-store.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {StaffCatalogService} from './catalog.service';

@Injectable()
export class CatalogResolver implements Resolve<Promise<any[]>> {

    constructor(
        private router: Router,
        private store: ServerStoreService,
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        console.debug('CatalogResolver:resolve()');

        return Promise.all([
            this.cat.fetchCcvms(),
            this.cat.fetchCmfs(),
            this.fetchSettings()
        ]);
    }

    fetchSettings(): Promise<any> {
        const promises = [];

        promises.push(
            this.store.getItem('eg.search.search_lib').then(
                id => this.staffCat.defaultSearchOrg = this.org.get(id)
            )
        );

        promises.push(
            this.store.getItem('eg.search.pref_lib').then(
                id => this.staffCat.prefOrg = this.org.get(id)
            )
        );

        return Promise.all(promises);
    }

}

