import {Injectable} from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
        ActivatedRouteSnapshot} from '@angular/router';
import {ServerStoreService} from '@eg/core/server-store.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {StaffCatalogService} from './catalog.service';
import {BasketService} from '@eg/share/catalog/basket.service';


@Injectable()
export class CatalogResolver implements Resolve<Promise<any[]>> {

    constructor(
        private router: Router,
        private store: ServerStoreService,
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService,
        private basket: BasketService
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        console.debug('CatalogResolver:resolve()');

        return Promise.all([
            this.cat.fetchCcvms(),
            this.cat.fetchCmfs(),
            this.fetchSettings(),
            this.basket.getRecordIds()
        ]);
    }

    fetchSettings(): Promise<any> {

        return this.store.getItemBatch([
            'eg.search.search_lib',
            'eg.search.pref_lib',
            'eg.search.adv_pane',
            'eg.catalog.results.count',
            'cat.holdings_show_empty_org',
            'cat.holdings_show_empty',
            'cat.marcedit.stack_subfields',
            'cat.marcedit.flateditor',
            'cat.holdings_show_copies',
            'cat.holdings_show_vols',
            'opac.staff_saved_search.size',
            'eg.catalog.search_templates',
            'opac.staff_saved_search.size'
        ]).then(settings => {
            this.staffCat.defaultSearchOrg =
                this.org.get(settings['eg.search.search_lib']);
            this.staffCat.prefOrg =
                this.org.get(settings['eg.search.pref_lib']);
            this.staffCat.defaultTab = settings['eg.search.adv_pane'];
            if (settings['eg.catalog.results.count']) {
               this.staffCat.defaultSearchLimit =
                  Number(settings['eg.catalog.results.count']);
            }
        });
    }
}

