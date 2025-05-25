import {Injectable, EventEmitter, TemplateRef} from '@angular/core';
import {tap} from 'rxjs';

/* Relay requests to/from the context menu directive and its
 * template container component */

export interface ContextMenuEntry {
    value?: string;
    label?: string;
    divider?: boolean;
}

export class ContextMenu {
    id: number;
    entries: ContextMenuEntry[];
}

@Injectable({providedIn: 'root'})
export class ContextMenuService {

    showMenuRequest: EventEmitter<ContextMenu>;
    menuItemSelected: EventEmitter<ContextMenuEntry>;

    menuTemplate: TemplateRef<any>;
    activeMenu: ContextMenu;

    constructor() {
        this.showMenuRequest = new EventEmitter<ContextMenu>();
        this.menuItemSelected = new EventEmitter<ContextMenuEntry>();
    }
}


