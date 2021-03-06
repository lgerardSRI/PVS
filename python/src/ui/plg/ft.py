import wx
import util
import logging
import pvscomm
import os.path
import evhdlr
from constants import *
from wx.lib.pubsub import setupkwargs, pub 
from ui.plugin import PluginPanel
import ui.images
import preference
import remgr

class FilesTreePlugin(PluginPanel):
    """This class provides an API for the files tree that is inside FilesTreeFrame"""
    
    def __init__(self, parent, definition):
        PluginPanel.__init__(self, parent, definition)
        self.tree = wx.TreeCtrl(self, wx.ID_ANY, style=wx.TR_HIDE_ROOT | wx.TR_HAS_BUTTONS | wx.TR_LINES_AT_ROOT | wx.TR_DEFAULT_STYLE | wx.SUNKEN_BORDER)
        self.history = []

        mainSizer = wx.BoxSizer(wx.VERTICAL)
        toolbar = wx.ToolBar(self, wx.ID_ANY, style = wx.TB_HORIZONTAL | wx.NO_BORDER)
        
        toolbarInfo = [ \
                       ["new.gif", "Create a new PVS file", evhdlr.onCreateNewFile], \
                       ["open.gif", "Open an existing PVS file", evhdlr.onOpenFile], \
                       ["save.gif", "Save file", evhdlr.onSaveFile], \
                       ["saveall.gif", "Save all files", evhdlr.onSaveAllFiles], \
                       ["context.png", "Change PVS context", evhdlr.onChangeContext], \
        ]
        self.toolbarButton = {}
        for imageName, tooltipText, command in toolbarInfo:
            buttonID = wx.NewId()
            toolbar.AddTool(buttonID, ui.images.getBitmap(imageName))
            wx.EVT_TOOL(self, buttonID, self.onToolboxButtonClicked)
            self.toolbarButton[buttonID] = command
            
        toolbar.Realize()
        mainSizer.Add(toolbar, 0)
        mainSizer.Add(self.tree, 1, wx.EXPAND, 0)
        self.SetSizer(mainSizer)
        
        imageList = wx.ImageList(16, 16)
        images = {LCONTEXT: ui.images.getFolderImage(), LFILE: ui.images.getPVSLogo(), LTHEORY: ui.images.getTheoryImage(), \
                  GREENFORMULA: ui.images.getGreenFormulaImage(), GRAYFORMULA: ui.images.getGrayFormulaImage(), LINACTIVECONTEXT: ui.images.getGrayFolderImage()}
        index = 0
        self.imageIndices = {LROOT: -1}
        for name, im in images.iteritems():
            imageList.Add(im)
            self.imageIndices[name] = index
            index = index + 1
        self.tree.AssignImageList(imageList)
        
        self.tree.Bind(wx.EVT_TREE_ITEM_MENU, self.showContextMenu)
        self.clearAll()
        pub.subscribe(self.addFile, PUB_ADDFILE)
        pub.subscribe(self.removeFile, PUB_CLOSEFILE)
        pub.subscribe(self.onFileSaved, PUB_FILESAVED)
        pub.subscribe(self.onFileIsTypechecked, PUB_FILETYPECHECKED)
        pub.subscribe(self.clearFileNodeChildren, PUB_FILEPARSING)
        pub.subscribe(self.pvsContextUpdated, PUB_UPDATEPVSCONTEXT)
        pub.subscribe(self.onFormulaUpdated, PUB_FORMULAUPDATE)
        self.tree.SetDropTarget(PVSFileDropTarget())
        
    def onToolboxButtonClicked(self, event):
        command = self.toolbarButton[event.GetId()]
        command(event)
        event.Skip()
        
    def clearAll(self):
        self.tree.DeleteAllItems()
        self.tree.AddRoot("", self.imageIndices[LROOT], -1, wx.TreeItemData({KIND: LROOT}))
        
    def pvsContextUpdated(self):
        newContext = preference.Preferences().getRecentContexts()[0]
        item = self.tree.GetFirstChild(self.tree.GetRootItem())[0]
        while item.IsOk():
            data = self.tree.GetItemPyData(item)
            if LCONTEXT in data:
                contextName = data[LCONTEXT]
                newImage = self.imageIndices[LCONTEXT] if newContext == contextName else self.imageIndices[LINACTIVECONTEXT]
                self.tree.SetItemImage(item, newImage)
            item = self.tree.GetNextSibling(item)
        
                
    def addContext(self, context):
        root = self.tree.GetRootItem()
        image = self.imageIndices[LCONTEXT] if context == pvscomm.PVSCommandManager().pvsContext else self.imageIndices[LINACTIVECONTEXT]
        self.tree.AppendItem(root, context, image, -1, wx.TreeItemData({LCONTEXT: context, KIND: LCONTEXT}))
    
    def removeContext(self, context):
        """remove a context from the tree"""
        logging.info("Removing context %s", context)
        contextNode = self.getContextNode(context)
        richEditorManager = remgr.RichEditorManager()
        fullnames = [self.tree.GetItemPyData(fileNode)[FULLNAME] for fileNode in self.getChildren(contextNode)]
        assert len(fullnames) > 0
        if richEditorManager.ensureFilesAreSavedToPoceed(fullnames):
            for fullname in fullnames:
                richEditorManager.handleCloseFileRequest(fullname)
                
    def addFile(self, fullname):
        """add a file to the tree"""
        logging.info("Adding file %s", fullname)
        directory = os.path.split(fullname)[0]
        contextNode = self.getContextNode(directory)
        if contextNode is None:
            self.addContext(directory)
            contextNode = self.getContextNode(directory)
        if self.getFileNode(fullname) is None:
            self.tree.AppendItem(contextNode, util.getFilenameFromFullPath(fullname), self.imageIndices[LFILE], -1, wx.TreeItemData({FULLNAME: fullname, KIND: LFILE}))
        self.tree.Expand(contextNode)        
    
    def removeFile(self, fullname):
        """remove a file from the tree"""
        logging.info("Removing file %s", fullname)
        fileNode = self.getFileNode(fullname)
        context = os.path.split(fullname)[0]
        contextNode = self.getContextNode(context)
        self.tree.Delete(fileNode)
        if not self.tree.ItemHasChildren(contextNode):
            self.tree.Delete(contextNode)
        
    def getContextNode(self, context):
        """return the tree node for a given context"""
        item = self.tree.GetFirstChild(self.tree.GetRootItem())[0]
        while item.IsOk():
            data = self.tree.GetItemPyData(item)
            if LCONTEXT in data:
                contextName = data[LCONTEXT]
                if context == contextName:
                    return item
            item = self.tree.GetNextSibling(item)
        logging.info("There is no context %s in the filetree", context)
        return None
        
    def getFileNode(self, fullname):
        """return the tree node for a given file"""
        directory = os.path.split(fullname)[0]
        contextNode = self.getContextNode(directory)
        item = self.tree.GetFirstChild(contextNode)[0]
        while item.IsOk():
            data = self.tree.GetItemPyData(item)
            if FULLNAME in data:
                nodeFullname = data[FULLNAME]
                if fullname == nodeFullname:
                    return item
            item = self.tree.GetNextSibling(item)
        logging.info("There is no %s in the filetree", fullname)
        return None
    
    def getTheoryNode(self, fullname, theoryname):
        fileNode = self.getFileNode(fullname)
        if fileNode is not None:
            item = self.tree.GetFirstChild(fileNode)[0]
            while item.IsOk():
                data = self.tree.GetItemPyData(item)                
                if ID_L in data:
                    itemName = data[ID_L]
                    if theoryname == itemName:
                        return item
                item = self.tree.GetNextSibling(item)
            logging.info("There is no theory %s in %s", theoryname, fullname)
        return None
                
    def getFormulaNode(self, fullname, theoryname, formulaname):
        theoryNode = self.getTheoryNode(fullname, theoryname)
        if theoryNode is not None:
            item = self.tree.GetFirstChild(theoryNode)[0]
            while item.IsOk():
                data = self.tree.GetItemPyData(item)                
                if data[LKIND] == LFORMULA:
                    itemName = data[ID_L]
                    if formulaname == itemName:
                        return item
                item = self.tree.GetNextSibling(item)
            logging.info("There is no formula %s in %s", formulaname, theoryname)
        return None
    
    def onFormulaUpdated(self, fullname, theoryname, formulaname, updatedata):
        item = self.getFormulaNode(fullname, theoryname, formulaname)
        if item is not None:
            isProved = updatedata["proved?"]
            self.tree.SetItemImage(item, self.imageIndices[GREENFORMULA if isProved else GRAYFORMULA])
            
                
    def getChildren(self, node):
        children = []
        child = self.tree.GetFirstChild(node)[0]
        while child.IsOk():
            children.append(child)
            child = self.tree.GetNextSibling(child)
        return children
                
    def showContextMenu(self, event):
        """display a relevant context menu when the user right-clicks on a node"""
        item = event.GetItem()
        data = self.tree.GetItemPyData(item)
        logging.debug("Event data: %s", data)
        kind = data[KIND] if KIND in data else None #TODO: Figure out what to do when KIND is absent (may be a PVS issue)
        menu = wx.Menu()
        pvsMode = pvscomm.PVSCommandManager().pvsMode
        items = self.getContextMenuItems(pvsMode, kind, data) # each item should be a pair of a label and a callback function.
        for label, callback in items:
            if isinstance(callback, wx.Menu):
                menu.AppendMenu(wx.ID_ANY, label, callback)
            else:
                ID = menu.Append(wx.ID_ANY, label, EMPTY_STRING, wx.ITEM_NORMAL).GetId()
                wx.EVT_MENU(menu, ID, callback)
        self.tree.GetParent().PopupMenu(menu, event.GetPoint())
        menu.Destroy()
        
    def getContextMenuItems(self, pvsMode, kind, data):
        items = []
        if not pvsMode in [PVS_MODE_OFF, PVS_MODE_LISP, PVS_MODE_PROVER, PVS_MODE_UNKNOWN]:
            logging.error("Unknown PVS mode: %s", pvsMode)
        if kind == LROOT:
            items = self.getContextMenuItemsForRoot(pvsMode, data)
        elif kind == LCONTEXT:
            items = self.getContextMenuItemsForPVSContext(pvsMode, data)
        elif kind == LFILE:
            items = self.getContextMenuItemsForFile(pvsMode, data)
        elif kind == LTHEORY:
            items = self.getContextMenuItemsForTheory(pvsMode, data)
        elif kind == LFORMULA:
            items = self.getContextMenuItemsForFormula(pvsMode, data)
        else:
            logging.error("Unknown kind: %s", kind)
        return items

    def getContextMenuItemsForRoot(self, pvsMode, data):
        return []
    
    def getContextMenuItemsForPVSContext(self, pvsMode, data):
        items = []
        if pvsMode == PVS_MODE_OFF:
            pass
        elif pvsMode == PVS_MODE_LISP or pvsMode == PVS_MODE_UNKNOWN:
            nodeContext = self.getSelectedNodeData()[LCONTEXT]
            if nodeContext != pvscomm.PVSCommandManager().pvsContext:
                items.append(("Make Active Context", self.onSetAsActiveContext))
        elif pvsMode == PVS_MODE_PROVER:
            pass
        items.append(("Close Context", self.onCloseContext))
        logging.debug("%d many items added to the context menu", len(items))
        return items
        
    def getContextMenuItemsForFile(self, pvsMode, data):
        fullname = data[FULLNAME]
        directory = os.path.split(fullname)[0]
        items = []
        if pvsMode == PVS_MODE_OFF:
            pass
        elif pvsMode == PVS_MODE_LISP and directory == pvscomm.PVSCommandManager().pvsContext:
            items.append((LABEL_TYPECHECK, self.onTypecheckFile))
        elif pvsMode == PVS_MODE_PROVER:
            pass
        elif pvsMode == PVS_MODE_UNKNOWN:
            pass
        items.append((LABEL_CLOSEFILE, self.onCloseFile))
        logging.debug("%d many items added to the context menu", len(items))
        return items
        
    def getContextMenuItemsForTheory(self, pvsMode, data):
        items = []
        if pvsMode == PVS_MODE_OFF:
            pass
        elif pvsMode == PVS_MODE_LISP:
            pass
        elif pvsMode == PVS_MODE_PROVER:
            pass
        elif pvsMode == PVS_MODE_UNKNOWN:
            pass
        logging.debug("%d many items added to the context menu", len(items))
        return items
        
    def getContextMenuItemsForFormula(self, pvsMode, data):
        items = []
        if pvsMode == PVS_MODE_OFF:
            pass
        elif pvsMode == PVS_MODE_LISP:
            items.append((LABEL_PROVE_FORMULA, self.onStartProver))
        elif pvsMode == PVS_MODE_PROVER:
            pass
        elif pvsMode == PVS_MODE_UNKNOWN:
            pass
        logging.debug("%d many items added to the context menu", len(items))
        return items
        
            
    def getSelectedNodeData(self):
        """return the node that is currently selected"""
        node = self.tree.GetSelection()
        data = self.tree.GetItemPyData(node)
        return data
    
    def onCloseContext(self, event):
        """onCloseContext is called when the user selects Close in the context menu"""
        context = self.getSelectedNodeData()[LCONTEXT]
        self.removeContext(context)
        
    def onSetAsActiveContext(self, event):
        """onSetAsActiveContext is called when the user wants to change the PVS context"""
        context = self.getSelectedNodeData()[LCONTEXT]
        pvscomm.PVSCommandManager().changeContext(context)
    
    def onCloseFile(self, event):
        """onCloseFile is called when the user selects Close in the context menu"""
        nodeFullname = self.getSelectedNodeData()[FULLNAME]
        remgr.RichEditorManager().handleCloseFileRequest(nodeFullname)
        
    def onTypecheckFile(self, event):
        """onTypecheckFile is called when the user selects Typecheck in the context menu"""
        nodeFullname = self.getSelectedNodeData()[FULLNAME]
        pvscomm.PVSCommandManager().typecheck(nodeFullname)
        
    def onStartProver(self, event):
        """onTypecheckFile is called when the user selects Typecheck in the context menu"""
        node = self.tree.GetSelection()
        parent = self.tree.GetItemParent(self.tree.GetItemParent(node))
        data = self.tree.GetItemPyData(node)
        parentData = self.tree.GetItemPyData(parent)
        theoryName = data[THEORY.lower()]
        formulaName = data[ID_L]
        fullname = parentData[FULLNAME]
        pvscomm.PVSCommandManager().startProver(fullname, theoryName, formulaName)
        
    def onFileIsTypechecked(self, fullname, result):
        """onFileIsTypechecked is called after typechecking a file and asking for the declarations in that file"""
        fileNode = self.getFileNode(fullname)
        logging.debug("%s was typechecked. Result is: %s", fullname, result)
        for item in result :
            if LTHEORY in item:
                theory = item[LTHEORY]
                theoryName = theory[ID_L]
                logging.info("Adding theory %s to %s", theoryName, fullname)
                declarations = theory[DECLS]
                theoryNode = self.tree.AppendItem(fileNode, theoryName, self.imageIndices[LTHEORY], -1, wx.TreeItemData(theory))
                for declaration in declarations:
                    kind = declaration[LKIND]
                    if kind == LFORMULA:
                        place = declaration[LPLACE]
                        isComplete = declaration["complete?"] == True
                        isProved = declaration["proved?"] == True
                        hasProofScript = declaration["has-proofscript?"] == True
                        formulaName = declaration[ID_L]
                        declaration[LTHEORY] = theoryName
                        self.tree.AppendItem(theoryNode, formulaName, self.imageIndices[GREENFORMULA if isProved else GRAYFORMULA], -1, wx.TreeItemData(declaration))
        self.tree.ExpandAllChildren(fileNode)        
        
    def onFileSaved(self, fullname, oldname=None):
        """remove the theories nodes from a file node"""
        self.clearFileNodeChildren(fullname) if oldname is None else self.clearFileNodeChildren(oldname)
        if oldname is not None:
            self.removeFile(oldname)
            self.addFile(fullname)
            #self.tree.SetItemPyData(fileNode, wx.TreeItemData({FULLNAME: fullname, KIND: LFILE}))
            #self.tree.SetItemText(fileNode, util.getFilenameFromFullPath(fullname))
            
    def clearFileNodeChildren(self, fullname):
        fileNode = self.getFileNode(fullname)
        self.tree.DeleteChildren(fileNode)
        
            

class PVSFileDropTarget(wx.FileDropTarget):
    def __init__(self):
        wx.FileDropTarget.__init__(self)

    def OnDropFiles(self, x, y, fullnames):
        logging.debug("These files were dropped: %s", fullnames)
        for fullname in fullnames:
            fileExtension = os.path.splitext(fullname)[1]
            if fileExtension == PVS_EXTENSION:
                util.openFile(fullname)


                                    