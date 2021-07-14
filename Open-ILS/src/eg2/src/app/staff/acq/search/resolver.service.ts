import {Injectable} from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
        ActivatedRouteSnapshot} from '@angular/router';
import {AttrDefsService} from './attr-defs.service';
import {AcqSearchService} from './acq-search.service';

@Injectable()
export class AttrDefsResolver implements Resolve<Promise<any[]>> {

    savedId: number = null;

    constructor(
        private router: Router,
        private attrDefs: AttrDefsService,
        private acqSearch: AcqSearchService
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        return this.attrDefs.fetchAttrDefs()
        .then(_ => this.acqSearch.loadUiPrefs());
    }

}
