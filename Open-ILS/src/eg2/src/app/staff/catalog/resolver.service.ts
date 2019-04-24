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

        return this.store.getItemBatch([
            'eg.search.search_lib',
            'eg.search.pref_lib'
        ]).then(settings => {
            this.staffCat.defaultSearchOrg =
                this.org.get(settings['eg.search.search_lib']);
            this.staffCat.prefOrg =
                this.org.get(settings['eg.search.pref_lib']);
        });
    }
}

