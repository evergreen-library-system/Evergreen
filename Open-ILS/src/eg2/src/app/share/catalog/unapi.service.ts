import {Injectable, EventEmitter} from '@angular/core';
import {OrgService} from '@eg/core/org.service';

/*
TODO: Add Display Fields to UNAPI
https://library.biz/opac/extras/unapi?id=tag::U2@bre/1{bre.extern,holdings_xml,mra}/BR1/0&format=mods32
*/

const UNAPI_PATH = '/opac/extras/unapi?id=tag::U2@';

interface UnapiParams {
    target: string; // bre, ...
    id: number | string; // 1 | 1,2,3,4,5
    extras: string; // {holdings_xml,mra,...}
    format: string; // mods32, marxml, ...
    orgId?: number; // org unit ID
    depth?: number; // org unit depth
}

@Injectable()
export class UnapiService {

    constructor(private org: OrgService) {}

    createUrl(params: UnapiParams): string {
        const depth = params.depth || 0;
        const org = params.orgId ? this.org.get(params.orgId) : this.org.root();

        return `${UNAPI_PATH}${params.target}/${params.id}${params.extras}/` +
            `${org.shortname()}/${depth}&format=${params.format}`;
    }

    getAsXmlDocument(params: UnapiParams): Promise<XMLDocument> {
        // XReq creates an XML document for us.  Seems like the right
        // tool for the job.
        const url = this.createUrl(params);
        return new Promise((resolve, reject) => {
            const xhttp = new XMLHttpRequest();
            xhttp.onreadystatechange = function() { // no () => {} !
                if (this.readyState === 4) {
                    if (this.status === 200) {
                        resolve(xhttp.responseXML);
                    } else {
                        reject(`UNAPI request failed for ${url}`);
                    }
                }
            };
            xhttp.open('GET', url, true);
            xhttp.send();
        });
    }
}


