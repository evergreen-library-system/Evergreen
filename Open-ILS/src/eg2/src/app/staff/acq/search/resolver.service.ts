import {Injectable} from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
        ActivatedRouteSnapshot} from '@angular/router';
import {AttrDefsService} from './attr-defs.service';

@Injectable()
export class AttrDefsResolver implements Resolve<Promise<any[]>> {

    savedId: number = null;

    constructor(
        private router: Router,
        private attrDefs: AttrDefsService,
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        return Promise.all([
            this.attrDefs.fetchAttrDefs()
        ]);
    }

}
