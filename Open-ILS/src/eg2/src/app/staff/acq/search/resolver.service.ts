import { Injectable, inject } from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
    ActivatedRouteSnapshot} from '@angular/router';
import {AttrDefsService} from './attr-defs.service';

@Injectable()
export class AttrDefsResolver implements Resolve<Promise<any[]>> {
    private router = inject(Router);
    private attrDefs = inject(AttrDefsService);


    savedId: number = null;

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        return Promise.all([
            this.attrDefs.fetchAttrDefs()
        ]);
    }

}
