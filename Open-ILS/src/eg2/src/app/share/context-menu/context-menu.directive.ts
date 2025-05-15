import {Input, Output, EventEmitter, Directive} from '@angular/core';
import {NgbPopover} from '@ng-bootstrap/ng-bootstrap';
import {ContextMenuService, ContextMenu, ContextMenuEntry} from './context-menu.service';


/* Import all of this stuff so we can pass it to our parent
 * class via its constructor */
/* eslint-disable no-duplicate-imports */
import {
    Inject, Injector, Renderer2, ElementRef, ViewContainerRef,
    NgZone, ChangeDetectorRef, ApplicationRef
} from '@angular/core';
import {DOCUMENT} from '@angular/common';
import {NgbPopoverConfig} from '@ng-bootstrap/ng-bootstrap';
/* eslint-enable no-duplicate-imports */
/* --- */

@Directive({
    selector: '[egContextMenu]',
    exportAs: 'egContextMenu'
})
export class ContextMenuDirective extends NgbPopover {

    // Only one active menu is allowed at a time.
    static activeDirective: ContextMenuDirective;
    static menuId = 0;

    triggers = 'contextmenu';
    popoverClass = 'eg-context-menu';

    menuEntries: ContextMenuEntry[] = [];
    menu: ContextMenu;

    @Input() set egContextMenu(menuEntries: ContextMenuEntry[]) {
        this.menuEntries = menuEntries;
    }

    @Output() menuItemSelected: EventEmitter<ContextMenuEntry>;

    constructor(
        p1: ElementRef<HTMLElement>, p2: Renderer2, p3: Injector,
        p5: ViewContainerRef, p6: NgbPopoverConfig,
        p7: NgZone, @Inject(DOCUMENT) p8: any, p9: ChangeDetectorRef,
        p10: ApplicationRef, private menuService: ContextMenuService) {

	super();

        this.menuItemSelected = new EventEmitter<ContextMenuEntry>();

        this.menuService.menuItemSelected.subscribe(
            (entry: ContextMenuEntry) => {

                // Only broadcast entry selection to my listeners if I'm
                // hosting the menu where the selection occurred.

                if (this.activeMenuIsMe()) {
                    this.menuItemSelected.emit(entry);

                    // Item selection via keyboard fails to close the menu.
                    // Force it closed.
                    this.cleanup();
                }
            });
    }

    activeMenuIsMe(): boolean {
        return (
            this.menu &&
            this.menuService.activeMenu &&
            this.menu.id === this.menuService.activeMenu.id
        );
    }

    // Close the active menu
    cleanup() {
        if (ContextMenuDirective.activeDirective) {
            ContextMenuDirective.activeDirective.close();
            ContextMenuDirective.activeDirective = null;
            this.menuService.activeMenu = null;
        }
    }

    open() {

        // In certain scenarios (e.g. right-clicking on another context
        // menu) an open popover will stay open.  Force it closed here.
        this.cleanup();

        if (!this.menuEntries ||
             this.menuEntries.length === 0) {
            return;
        }

        this.menu = new ContextMenu();
        this.menu.id = ContextMenuDirective.menuId++;
        this.menu.entries = this.menuEntries;

        this.menuService.activeMenu = this.menu;
        this.menuService.showMenuRequest.emit(this.menu);
        this.ngbPopover = this.menuService.menuTemplate;

        ContextMenuDirective.activeDirective = this;

        super.open();
    }
}


