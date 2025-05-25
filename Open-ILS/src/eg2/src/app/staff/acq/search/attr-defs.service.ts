import {Injectable} from '@angular/core';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject} from '@eg/core/idl.service';

@Injectable()
export class AttrDefsService {

    attrDefs: {[code: string]: IdlObject};

    constructor(
        private pcrud: PcrudService
    ) {
        this.attrDefs = {};
    }

    fetchAttrDefs(): Promise<void> {
        if (Object.keys(this.attrDefs).length) {
            return Promise.resolve();
        }
        return new Promise((resolve, reject) => {
            this.pcrud.retrieveAll('acqliad', {},
                {atomic: true}
            ).subscribe(list => {
                list.forEach(acqliad => {
                    this.attrDefs[acqliad.code()] = acqliad;
                });
                resolve();
            });
        });
    }

}
