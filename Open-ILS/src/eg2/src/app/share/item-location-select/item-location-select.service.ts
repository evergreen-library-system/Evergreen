import {Injectable, EventEmitter} from '@angular/core';
import {Observable} from 'rxjs';
import {switchMap, map} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';

@Injectable()
export class ItemLocationService {

    filterOrgsCache: {[perm: string]: number[]} = {};
    locationCache: {[id: number]: IdlObject} = {};
}
