
import {Component, ViewChild, OnInit} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {IdlService} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CompositeNewPointComponent} from './composite-new.component';
import {StringComponent} from '@eg/share/string/string.component';

@Component({
    templateUrl: './composite-def.component.html'
})

export class CompositeDefComponent implements OnInit {
    currentId: number; // ccvm id

    // these values displayed at top of page
    code: string;
    attribute: string;
    value: string;

    // data used to build tree
    tree: Tree;
    treeIndex = 2; // 1 is always root, so start at 2
    idmap: any = {};
    recordAttrDefs: any = {};
    fetchAttrs: any[] = [];
    codedValueMaps: any = {};

    newPointType: string;
    @ViewChild('newPoint', { static: true }) newPoint: CompositeNewPointComponent;

    changesMade = false;
    noSavedTreeData = false;

    @ViewChild('saveSuccess', { static: true }) saveSuccess: StringComponent;
    @ViewChild('saveFail', { static: true }) saveFail: StringComponent;

    constructor(
        private pcrud: PcrudService,
        private router: Router,
        private route: ActivatedRoute,
        private idl: IdlService,
        private toast: ToastService,
    ) {
    }

    ngOnInit() {
        this.currentId = parseInt(this.route.snapshot.paramMap.get('id'), 10);
        this.getRecordAttrDefs();
    }

    getRecordAttrDefs = () => {
        this.pcrud.retrieveAll('crad', {order_by: {crad: 'name'}}, {atomic: true}).subscribe(defs => {
            defs.forEach((def) => {
                this.recordAttrDefs[def.name()] = def;
            });
            this.getCodedMapValues();
        });
    };

    getCodedMapValues = () => {
        this.pcrud.search('ccvm', {'id': this.currentId},
            {flesh: 1, flesh_fields: {ccvm: ['composite_def', 'ctype']} }).toPromise().then(
            res => {
                this.code = res.code();
                this.value = res.value();
                this.attribute = res.ctype().label();
                if (res.composite_def()) {
                    this.buildTreeStart(res.composite_def().definition());
                } else {
                    this.noSavedTreeData = true;
                }
            });
    };

    createNodeLabels = () => {
        for (const key of Object.keys(this.idmap)) {
            const nodeCallerData = this.idmap[key].callerData.point;
            if (nodeCallerData.typeId) {
                for (const id of Object.keys(this.codedValueMaps)) {
                    const m = this.codedValueMaps[id];
                    if ((m.code() === nodeCallerData.valueId) &&
                        (m.ctype() === nodeCallerData.typeId)) {
                        nodeCallerData.valueLabel = m.value();
                    }
                }
                this.idmap[key].label = this.buildLabel(nodeCallerData.typeLabel, nodeCallerData.typeId,
                    nodeCallerData.valueLabel, nodeCallerData.valueId);
            }
        }
    };

    expressionAsString = () => {
        if (!this.tree) { return ''; }

        const renderNode = (node: TreeNode): string => {
            const lbl = node.label;
            if (!node) { return ''; }
            if (node.children.length) {
                let negative = '';
                let startParen = '( ';
                let endParen = ' )';
                if (lbl === 'NOT') {
                    negative = 'NOT ';
                    startParen = ''; // parentheses for NOT are redundant
                    endParen = '';
                }
                if (this.tree.findParentNode(node) === null) { // no parentheses for root node
                    startParen = '';
                    endParen = '';
                }
                return negative + startParen + node.children.map(renderNode).join(
                    ' ' + node.label +  ' ') + endParen;
            } else if ((lbl !== 'NOT') && (lbl !== 'AND') && (lbl !== 'OR')) {
                return node.callerData.point.valueLabel;
            } else {
                return '()';
            }
        };
        return renderNode(this.tree.rootNode);
    };

    buildTreeStart = (def) => {
        if (def) {
            const nodeData = JSON.parse(def);
            let rootNode;
            if (Array.isArray(nodeData)) {
                rootNode = this.addBooleanRootNode('OR');
                nodeData.forEach(n => {
                    this.buildTree(rootNode, n);
                });
            } else {
                if (nodeData['_not']) {
                    rootNode = this.addBooleanRootNode('NOT');
                    this.buildTree(rootNode, nodeData['_not']);
                } else if (nodeData['0']) {
                    rootNode = this.addBooleanRootNode('AND');
                    for (const key of Object.keys(nodeData)) {
                        this.buildTree(rootNode, nodeData[key]);
                    }
                } else { // root node is record
                    const newRootValues = {
                        typeLabel: this.recordAttrDefs[nodeData._attr].label(),
                        typeId: nodeData['_attr'],
                        valueLabel: null,
                        valueId: nodeData['_val'],
                    };
                    rootNode = {
                        values: newRootValues
                    };
                    rootNode = this.addRecordRootNode(rootNode);
                    this.fetchAttrs.push({'-and' : {ctype: nodeData['_attr'], code: nodeData['_val']}});
                }
            }
            if (this.fetchAttrs.length > 0) {
                this.pcrud.search('ccvm', {'-or' : this.fetchAttrs}).subscribe(
                    { next: data => {
                        this.codedValueMaps[data.id()] = data;
                    }, error: (err: unknown) => {
                        console.debug(err);
                    }, complete: () => {
                        this.createNodeLabels();
                    } }
                );
            }
        }
    };

    buildTree = (parentNode, nodeData) => {
        let dataIsArray = false;
        if (Array.isArray(nodeData)) { dataIsArray = true; }
        const point = {
            id: null,
            expanded: true,
            children: [],
            parent: parentNode.id,
            label: null,
            typeLabel: null,
            typeId: null,
            valueLabel: null,
            valueId: null,
        };
        if (nodeData[0] || (nodeData['_not']) || dataIsArray) {
            this.buildTreeBoolean(nodeData, dataIsArray, point, parentNode);
        } else { // not boolean. it's a record
            this.buildTreeRecord(nodeData, point, parentNode);
        }
    };

    buildTreeBoolean = (nodeData: any, dataIsArray: any, point: any, parentNode) => {
        if (dataIsArray) {
            point.label = 'OR';
        } else if (nodeData['_not']) {
            point.label = 'NOT';
        } else if (nodeData[0]) {
            point.label = 'AND';
        } else {
            console.debug('Error.  No boolean value found');
        }
        point.id = this.treeIndex++;
        const newNode: TreeNode = new TreeNode({
            id: point.id,
            expanded: true,
            label:  point.label,
            callerData: {point: point}
        });
        parentNode.children.push(newNode);
        this.idmap[point.id + ''] = newNode;
        if (dataIsArray) {
            nodeData.forEach(n => {
                this.buildTree(newNode, n);
            });
        } else if (nodeData['_not']) {
            this.buildTree(newNode, nodeData['_not']);
        } else if (nodeData[0]) {
            for (const key of Object.keys(nodeData)) {
                this.buildTree(newNode, nodeData[key]);
            }
        } else {
            console.debug('Error building tree');
        }
    };

    buildTreeRecord = (nodeData: any, point: any, parentNode) => {
        point.typeLabel = this.recordAttrDefs[nodeData._attr].label();
        point.typeId = nodeData._attr;
        point.valueId = nodeData._val;
        this.fetchAttrs.push({'-and' : {ctype : nodeData._attr, code : nodeData._val}});
        point.id = this.treeIndex++;
        const newNode: TreeNode = new TreeNode({
            id: point.id,
            expanded: true,
            label:  null,
            callerData: {point: point}
        });
        parentNode.children.push(newNode);
        this.idmap[point.id + ''] = newNode;
    };

    createNewTree = () => {
        this.changesMade = true;
        this.treeIndex = 2;
        if (this.newPointType === 'bool') {
            this.addBooleanRootNode(this.newPoint.values.boolOp);
        } else {
            this.addRecordRootNode(this.newPoint);
        }
    };

    addBooleanRootNode = (boolOp: any) => {
        const point = { id: 1, label: boolOp, children: []};
        const node: TreeNode = new TreeNode({id: 1, label: boolOp, children: [],
            callerData: {point: point}});
        this.idmap['1'] = node;
        this.tree = new Tree(node);
        return node;
    };

    addRecordRootNode = (record: any) => {
        const point = { id: 1, expanded: true, children: [], label: null, typeLabel: null,
            typeId: null, valueLabel: null, valueId: null};
        point.typeLabel = record.values.typeLabel;
        point.typeId = record.values.typeId;
        point.valueLabel = record.values.valueLabel;
        point.valueId = record.values.valueId;
        const fullLabel = this.buildLabel(point.typeLabel, point.typeId, point.valueLabel, point.valueId);
        const node: TreeNode = new TreeNode({ id: 1, label: fullLabel, children: [],
            callerData: {point: point}});
        this.idmap['1'] = node;
        this.tree = new Tree(node);
        return node;
    };

    buildLabel = (tlbl, tid, vlbl, vid) => {
        return tlbl + ' (' + tid + ') => ' + vlbl + ' (' + vid + ')';
    };

    nodeClicked(node: TreeNode) {
        console.debug('Node clicked on: ' + node.label);
    }

    deleteTree = () => {
        this.tree = null;
        this.idmap = {};
        this.treeIndex = 2;
        this.changesMade = true;
    };

    deleteNode = () => {
        this.changesMade = true;
        if (this.isRootNode()) {
            this.deleteTree();
        } else {
            this.tree.removeNode(this.tree.selectedNode());
        }
    };

    hasSelectedNode(): boolean {
        if (this.tree) {
            return Boolean(this.tree.selectedNode());
        }
    }

    isRootNode(): boolean {
        const node = this.tree.selectedNode();
        if (node && this.tree.findParentNode(node) === null) {
            return true;
        }
        return false;
    }

    selectedIsBool(): boolean {
        if (!this.tree) { return false; }
        if (this.tree.selectedNode()) {
            const label = this.tree.selectedNode().label;
            if (label === 'AND' || label === 'NOT' || label === 'OR') { return true; }
        }
        return false;
    }

    // Disable this:
    // 1. if no node selected
    // 2. if trying to add to a non-boolean record
    // 3. if trying to add more than 1 child to a NOT
    // 4. if trying to add NOT to an existing NOT
    // 5. if trying to add before user has made selection of new value or operator
    addButtonDisabled(): boolean {
        if (!this.hasSelectedNode()) { return true; }
        if (!this.selectedIsBool()) { return true; }
        if ((this.tree.selectedNode().label === 'NOT') &&
            (this.tree.selectedNode().children.length > 0)) { return true; }
        if ((this.tree.selectedNode().label === 'NOT') &&
            (this.newPoint.values.boolOp === 'NOT')) { return true; }
        if (this.newPointType === 'attr' &&
            (this.newPoint.values.typeId.length > 0) &&
            (this.newPoint.values.valueId.length > 0)) { return false; }
        if (this.newPointType === 'bool' &&
            (this.newPoint.values.boolOp.length > 0)) { return false; }
        return true;
    }

    // Disable this:
    // 1. if no node selected
    // 2. if trying to replace a boolean with a non-boolean or vice versa
    // 3. if trying to replace before user has made selection of new value or operator
    replaceButtonDisabled(): boolean {
        if (!this.hasSelectedNode()) { return true; }
        if (this.newPointType === 'attr' && !this.selectedIsBool() &&
            (this.newPoint.values.typeId.length > 0) &&
            (this.newPoint.values.valueId.length > 0)) { return false; }
        if (this.newPointType === 'bool' && this.selectedIsBool() &&
            (this.newPoint.values.boolOp.length > 0)) { return false; }
        return true;
    }

    // disabled until you select a type and select values for that type
    newTreeButtonDisabled(): boolean {
        if ((this.newPointType === 'bool') && (this.newPoint.values.boolOp.length > 0)) {
            return false;
        }
        if ((this.newPointType === 'attr') && (this.newPoint.values.typeId.length > 0) &&
            (this.newPoint.values.valueId.length > 0)) { return false; }
        return true;
    }

    back() {
        this.router.navigate(['/staff/admin/server/config/coded_value_map']);
    }

    saveTree = () => {
        const recordToSave = this.idl.create('ccraed');
        recordToSave.coded_value(this.currentId);
        const expression = this.exportTree(this.idmap['1']);
        const jsonStr = JSON.stringify(expression);
        recordToSave.definition(jsonStr);
        if (this.noSavedTreeData) {
            this.pcrud.create(recordToSave).subscribe(
                { next: ok => {
                    this.saveSuccess.current().then(str => this.toast.success(str));
                    this.noSavedTreeData = false;
                }, error: (err: unknown) => {
                    this.saveFail.current().then(str => this.toast.danger(str));
                } }
            );
        } else {
            this.pcrud.update(recordToSave).subscribe(
                { next: async (ok) => {
                    this.saveSuccess.current().then(str => this.toast.success(str));
                }, error: async (err: unknown) => {
                    this.saveFail.current().then(str => this.toast.danger(str));
                } }
            );
        }
    };

    exportTree(node: TreeNode): any {
        const lbl = node.label;
        if ((lbl !== 'NOT') && (lbl !== 'AND') && (lbl !== 'OR')) {
            const retval = {_attr: node.callerData.point.typeId, _val: node.callerData.point.valueId};
            return retval;
        }
        if (lbl === 'NOT') {
            return {_not : this.exportTree(node.children[0])}; // _not nodes may only have one child
        }
        let compiled;
        for (let i = 0; i < node.children.length; i++) {
            const child = node.children[i];
            if (!compiled) {
                if (node.label === 'OR') {
                    compiled = [];
                } else {
                    compiled = {};
                }
            }
            compiled[i] = this.exportTree(child);
        }
        return compiled;
    }

    addChildNode(replace?: boolean) {
        const targetNode: TreeNode = this.tree.selectedNode();
        this.changesMade = true;
        const point = {
            id: null,
            expanded: true,
            children: [],
            parent: targetNode.id,
            label: null,
            typeLabel: null,
            typeId: null,
            valueLabel: null,
            valueId: null,
        };

        const node: TreeNode = new TreeNode({
            callerData: {point: point},
            id: point.id,
            label: null
        });

        if (this.newPoint.values.pointType === 'bool') {
            point.label = this.newPoint.values.boolOp;
            node.label = point.label;
        } else {
            point.typeLabel = this.newPoint.values.typeLabel;
            point.valueLabel = this.newPoint.values.valueLabel;
            point.typeId = this.newPoint.values.typeId;
            point.valueId = this.newPoint.values.valueId;
        }
        if (replace) {
            if (this.newPoint.values.pointType === 'bool') {
                targetNode.label = point.label;
            } else {
                targetNode.label = this.buildLabel(point.typeLabel, point.typeId, point.valueLabel,
                    point.valueId);
            }
            targetNode.callerData.point = point;
        } else {
            point.id = this.treeIndex;
            node.id = this.treeIndex++;
            if (this.newPoint.values.pointType === 'bool') {
                node.label = point.label;
            } else {
                node.label = this.buildLabel(point.typeLabel, point.typeId, point.valueLabel,
                    point.valueId);
            }
            point.parent = targetNode.id;
            targetNode.children.push(node);
            this.idmap[point.id + ''] = node;
        }
    }

}
