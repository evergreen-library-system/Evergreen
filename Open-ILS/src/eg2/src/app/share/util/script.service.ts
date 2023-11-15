/* eslint-disable brace-style */
import {Injectable} from '@angular/core';
import { ScriptStore } from './script.store';
import { OrgService } from '@eg/core/org.service';

declare var document: any; // eslint-disable-line no-var

@Injectable()
export class ScriptService {

    private scripts: any = {};

    constructor(private org: OrgService) {
        ScriptStore.forEach((script: any) => {
        // a script may have both a URL and an OU setting that replaces it
            if (script.setting) {
                this.org.settings([script.setting]).then(
                    setting => {
                        this.scripts[script.name] = {
                            loaded: false,
                            src: setting[script.setting] || script.src,
                            reloadable: script.reloadable
                        };
                    }
                );
            }
            // if there is no setting, just use the URL
            else {
                this.scripts[script.name] = {
                    loaded: false,
                    src: script.src,
                    reloadable: script.reloadable
                };
            }

        });
    }

    load(...scripts: string[]) {
        const promises: any[] = [];
        scripts.forEach((script) => promises.push(this.loadScript(script)));
        return Promise.all(promises);
    }

    loadScript(name: string, params?: any) {
        console.debug('Loading script: ' + name + ' with params ', params);
        return new Promise((resolve, reject) => {
        // resolve if already loaded
            if (this.scripts[name].loaded && this.scripts[name].reloadable !== true) {
                resolve({script: name, loaded: true, status: 'Already Loaded'});
            } else {
                const reload = this.scripts[name].loaded;
                this.scripts[name].loaded = false;

                // load script
                let loadsrc = this.scripts[name].src;
                if (params !== undefined && Object.keys(params).length > 0) {
                    loadsrc += '?' + Object.keys(params)
                        .map(function (k) {return `${k}=${encodeURIComponent(params[k])}`;})
                        .join('&');
                }

                const script = document.createElement('script');
                script.type = 'text/javascript';
                script.src = loadsrc;
                script.onerror = (error: any) => resolve({script: name, loaded: false, status: 'Loaded'});
                script.onload = () => {
                    this.scripts[name].loaded = true;
                    const status = reload ? 'Reloaded' : 'Loaded';
                    resolve({script: name, loaded: true, status: status});
                };

                document.getElementsByTagName('head')[0].appendChild(script);
            }
        });
    }

}
