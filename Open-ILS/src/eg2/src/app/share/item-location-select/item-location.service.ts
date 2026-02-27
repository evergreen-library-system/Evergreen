import {inject, Injectable} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { memoizeRetrieveByKeyFn } from '../memoize';

@Injectable({providedIn: 'root'})
export class ItemLocationService {
    getById = memoizeRetrieveByKeyFn((id: number) => this.pcrud.retrieve('acpl', id));

    filterOrgsCache: {[perm: string]: number[]} = {};
    locationCache: {[id: number]: IdlObject} = {};

    private pcrud = inject(PcrudService);
}
