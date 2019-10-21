import {Component, OnInit, ViewChild, AfterViewInit, Input} from '@angular/core';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {StringService} from '@eg/share/string/string.service';
import {MatchSetNewPointComponent} from './match-set-new-point.component';

@Component({
  selector: 'eg-match-set-expression',
  templateUrl: 'match-set-expression.component.html'
})
export class MatchSetExpressionComponent implements OnInit {

    // Match set arrives from parent async.
    matchSet_: IdlObject;
    @Input() set matchSet(ms: IdlObject) {
        this.matchSet_ = ms;
        if (ms && !this.initDone) {
            this.matchSetType = ms.mtype();
            this.initDone = true;
            this.refreshTree();
        }
    }

    tree: Tree;
    initDone: boolean;
    matchSetType: string;
    changesMade: boolean;

    // Current type of new match point
    newPointType: string;
    newId: number;

    @ViewChild('newPoint', { static: true }) newPoint: MatchSetNewPointComponent;

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        private net: NetService,
        private auth: AuthService,
        private org: OrgService,
        private strings: StringService
    ) {
        this.newId = -1;
    }

    ngOnInit() {}

    refreshTree(): Promise<any> {
        if (!this.matchSet_) { return Promise.resolve(); }

        return this.pcrud.search('vmsp',
            {match_set: this.matchSet_.id()}, {},
            {atomic: true, authoritative: true}
        ).toPromise().then(points => {
            if (points.length > 0) {
                this.ingestMatchPoints(points);
            } else {
                this.addRootNode();
            }
        });
    }

    // When creating a new tree, add a stub boolean node
    // as the root so the tree has something to render.
    addRootNode() {

        const point = this.idl.create('vmsp');
        point.id(this.newId--);
        point.isnew(true);
        point.match_set(this.matchSet_.id());
        point.children([]);
        point.bool_op('AND');

        const node: TreeNode = new TreeNode({
            id: point.id(),
            callerData: {point: point}
        });

        this.tree = new Tree(node);
        this.setNodeLabel(node, point);
    }

    // Tree-ify a set of match points.
    ingestMatchPoints(points: IdlObject[]) {
        const nodes = [];
        const idmap: any = {};

        // massage data, create tree nodes
        points.forEach(point => {

            point.negate(point.negate() === 't' ? true : false);
            point.heading(point.heading() === 't' ? true : false);
            point.children([]);

            const node = new TreeNode({
                id: point.id(),
                expanded: true,
                callerData: {point: point}
            });
            idmap[node.id + ''] = node;
            this.setNodeLabel(node, point).then(() => nodes.push(node));
        });

        // apply the tree parent/child relationships
        points.forEach(point => {
            const node = idmap[point.id() + ''];
            if (point.parent()) {
                idmap[point.parent() + ''].children.push(node);
            } else {
                this.tree = new Tree(node);
            }
        });
    }

    setNodeLabel(node: TreeNode, point: IdlObject): Promise<any> {
        if (node.label) { return Promise.resolve(null); }
        return Promise.all([
            this.getPointLabel(point, true).then(txt => node.label = txt),
            this.getPointLabel(point, false).then(
                txt => node.callerData.slimLabel = txt)
        ]);
    }

    getPointLabel(point: IdlObject, showmatch?: boolean): Promise<string> {
        return this.strings.interpolate(
            'staff.cat.vandelay.matchpoint.label',
            {point: point, showmatch: showmatch}
        );
    }

    nodeClicked(node: TreeNode) {}

    deleteNode() {
        this.changesMade = true;
        const node = this.tree.selectedNode();
        this.tree.removeNode(node);
    }

    hasSelectedNode(): boolean {
        return Boolean(this.tree.selectedNode());
    }

    isRootNode(): boolean {
        const node = this.tree.selectedNode();
        if (node && this.tree.findParentNode(node) === null) {
            return true;
        }
        return false;
    }

    selectedIsBool(): boolean {
        if (this.tree) {
            const node = this.tree.selectedNode();
            return node && node.callerData.point.bool_op();
        }
        return false;
    }

    addChildNode() {
        this.changesMade = true;

        const pnode = this.tree.selectedNode();
        const point = this.idl.create('vmsp');
        point.id(this.newId--);
        point.isnew(true);
        point.parent(pnode.id);
        point.match_set(this.matchSet_.id());
        point.children([]);

        const ptype = this.newPoint.values.pointType;

        if (ptype === 'bool') {
            point.bool_op(this.newPoint.values.boolOp);

        } else {

            if (ptype === 'attr') {
                point.svf(this.newPoint.values.recordAttr);

            } else if (ptype === 'marc') {
                point.tag(this.newPoint.values.marcTag);
                point.subfield(this.newPoint.values.marcSf);
            } else if (ptype === 'heading') {
                point.heading(true);
            }

            point.negate(this.newPoint.values.negate);
            point.quality(this.newPoint.values.matchScore);
        }

        const node: TreeNode = new TreeNode({
            id: point.id(),
            callerData: {point: point}
        });

        // Match points are added to the DB only when the tree is saved.
        this.setNodeLabel(node, point).then(() => pnode.children.push(node));
    }

    expressionAsString(): string {
        if (!this.tree) { return ''; }

        const renderNode = (node: TreeNode): string => {
            if (!node) { return ''; }

            if (node.children.length) {
                return '(' + node.children.map(renderNode).join(
                    ' ' + node.callerData.slimLabel + ' ') + ')';
            } else if (!node.callerData.point.bool_op()) {
                return node.callerData.slimLabel;
            } else {
                return '()';
            }
        };

        return renderNode(this.tree.rootNode);
    }

    // Server API deletes and recreates the tree on update.
    // It manages parent/child relationships via the children array.
    // We only need send the current tree in a form the API recognizes.
    saveTree(): Promise<any> {


        const compileTree = (node?: TreeNode) => {

            if (!node) { node = this.tree.rootNode; }

            const point = node.callerData.point;

            node.children.forEach(child =>
                point.children().push(compileTree(child)));

            return point;
        };

        const rootPoint: IdlObject = compileTree();

        return this.net.request(
            'open-ils.vandelay',
            'open-ils.vandelay.match_set.update',
            this.auth.token(), this.matchSet_.id(), rootPoint
        ).toPromise().then(
            ok => this.refreshTree(),
            err => console.error(err)
        );
    }
}

