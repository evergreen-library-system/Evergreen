import { Component, OnInit, ViewChild, AfterViewInit, TemplateRef, ViewEncapsulation, inject } from '@angular/core';
import {ContextMenuService, ContextMenu, ContextMenuEntry} from './context-menu.service';


@Component({
    selector: 'eg-context-menu-container',
    templateUrl: './context-menu-container.component.html',
    styleUrls: ['context-menu-container.component.css'],
    /* Our CSS affects the style of the popover, which may
   * be beyond our reach for standard view encapsulation */
    encapsulation: ViewEncapsulation.None,
    imports: []
})

export class ContextMenuContainerComponent implements OnInit, AfterViewInit {
    private menuService = inject(ContextMenuService);


    menuEntries: ContextMenuEntry[] = [];
    @ViewChild('menuTemplate', {static: false}) menuTemplate: TemplateRef<any>;

    ngOnInit() {
        this.menuService.showMenuRequest.subscribe(
            (menu: ContextMenu) => {
                this.menuEntries = menu.entries;
            });
    }

    ngAfterViewInit() {
        this.menuService.menuTemplate = this.menuTemplate;
    }

    entryClicked(entry: ContextMenuEntry) {
        this.menuService.menuItemSelected.emit(entry);
    }
}

