import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {Location} from '@angular/common';
import {of} from 'rxjs';
import {NgbNav} from '@ng-bootstrap/ng-bootstrap';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ReporterService, SRTemplate} from '../share/reporter.service';
import {Tree, TreeNode} from '@eg/share/tree/tree';

@Component({
    templateUrl: './reporter.component.html',
    styleUrls: ['./reporter.component.css'],
})

export class FullReporterComponent implements OnInit {

    @ViewChild('newF', { static: true} ) newFolderString: StringComponent;
	@ViewChild('promptNewFolder', { static: true }) newFolderDialog: PromptDialogComponent;

	templateSearchFolder: IdlObject = null;
	templateSearchString = '';
	templateSearchField = '';

	currentFolder: IdlObject = null;

	managableFolderType = false;
	rerenderGridArea: Array<number> = [1];
	rerenderSearchArea: Array<number> = [1];

	constructor(
        private route: ActivatedRoute,
        private router: Router,
        private location: Location,
        private toast: ToastService,
        private evt: EventService,
        private idl: IdlService,
        private pcrud: PcrudService,
        public RSvc: ReporterService
	) {
	}

	getMyFolders() {
	    return this.RSvc.myFolderTrees;
	}

	searchGridRender() {
	    this.RSvc.currentFolderType = 'rtf';
	    this.rerenderSearchArea[0]++;
	}

	templateSearchFolderNodeSelected(node) {
	    if (node.callerData.folderIdl || node.id === 'my-templates') { // selecting an extant folder
	        this.templateSearchFolder = node.callerData.folderIdl;
	        this.searchGridRender();
	    } else {
	        node.toggleExpand();
	    }
	}

	folderNodeSelected(node) {
	    if (node.callerData.folderIdl) { // selecting an extant folder
	        this.RSvc.currentFolderType = node.callerData.folderIdl.classname;
	        switch (this.RSvc.currentFolderType) {
	            case 'rtf':
	                this.currentFolder = this.RSvc.templateFolder = node.callerData.folderIdl;
	                break;
	            case 'rrf':
	                this.currentFolder = this.RSvc.reportFolder = node.callerData.folderIdl;
	                break;
	            case 'rof':
	                this.currentFolder = this.RSvc.outputFolder = node.callerData.folderIdl;
	                break;
	        }
	    } else {
	        this.RSvc.currentFolderType = node.callerData.type + '-manager';
	        if (node.id.match(/^shared-by/)) {
	            node.toggleExpand();
	        }
	    }
	    this.managableFolderType = node.stateFlag;
	    this.rerenderGridArea[0]++;
	}

	newFolder($event) {
	    const new_type = this.RSvc.currentFolderType.split('-')[0];
	    if (new_type) {
	        this.newFolderString.current({})
    	    .then(str => {
	            this.newFolderDialog.dialogBody = str;
    	        this.newFolderDialog.promptValue = this.RSvc.lastNewFolderName;
        	    this.newFolderDialog.open().subscribe( new_name => {
            	    if ( new_name ) {
                	    this.RSvc.newTypedFolder(new_name, new_type);
	                }
    	        });
        	});
	    }
	}

	getSharedFolders() {
	    return this.RSvc.sharedFolderTrees;
	}

	ngOnInit() {
	}
}
