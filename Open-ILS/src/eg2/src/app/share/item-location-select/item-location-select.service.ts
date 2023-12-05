import {Injectable} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';

@Injectable()
export class ItemLocationService {

    filterOrgsCache: {[perm: string]: number[]} = {};
    locationCache: {[id: number]: IdlObject} = {};
}
