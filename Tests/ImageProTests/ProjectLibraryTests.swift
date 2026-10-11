import XCTest
@testable import ImagePro

final class ProjectLibraryTests:XCTestCase {
  @MainActor func makeStore()->EditorStore {
    let store = EditorStore(loadRecovery:false)
    store.libraryOrder = [];store.projectFolders = [];store.recentProjects = []
    return store
  }
  func testLegacyFolderDecodesAtRoot() throws {
    let folder = ProjectFolder(name:"旧文件夹")
    let data = try JSONEncoder().encode(folder)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
    object.removeValue(forKey:"parentID")
    let decoded = try JSONDecoder().decode(ProjectFolder.self,from:JSONSerialization.data(withJSONObject:object))
    XCTAssertNil(decoded.parentID);XCTAssertEqual(decoded.id,folder.id)
  }
  @MainActor func testMixedOrderingPersistsFolderBetweenProjects() throws {
    let store = makeStore()
    store.newProject(name:"A",width:100,height:100,background:nil);let a = store.active.id.uuidString
    store.newProject(name:"B",width:100,height:100,background:nil);let b = store.active.id.uuidString
    store.createProjectFolder(name:"分类");let folder = try XCTUnwrap(store.projectFolders.first)
    store.reorderStartPageProject(identifier:folder.libraryIdentifier,before:b)
    XCTAssertEqual(store.libraryOrder,[a,folder.libraryIdentifier,b])
    store.reorderStartPageProject(identifier:a,before:folder.libraryIdentifier,after:true)
    XCTAssertEqual(store.libraryOrder,[folder.libraryIdentifier,a,b])
  }
  @MainActor func testNestedMovesRejectCyclesAndCanReturnToRoot() throws {
    let store = makeStore();store.createProjectFolder(name:"A")
    let a = try XCTUnwrap(store.projectFolders.first)
    store.createProjectFolder(name:"B",parentID:a.id)
    let b = try XCTUnwrap(store.projectFolders.last)
    store.createProjectFolder(name:"C",parentID:b.id)
    let c = try XCTUnwrap(store.projectFolders.last)
    XCTAssertFalse(store.moveStartPageLibraryItem(a.libraryIdentifier,to:c.id))
    XCTAssertFalse(store.moveStartPageLibraryItem(b.libraryIdentifier,to:b.id))
    XCTAssertFalse(store.moveStartPageLibraryItem(c.libraryIdentifier,to:UUID()))
    XCTAssertEqual(store.projectFolderTrail(c.id).map(\.id),[a.id,b.id,c.id])
    XCTAssertTrue(store.moveStartPageLibraryItem(b.libraryIdentifier,to:nil))
    XCTAssertEqual(store.projectFolderTrail(c.id).map(\.id),[b.id,c.id])
  }
  @MainActor func testMovingProjectSynchronizesSavedEntryAndOpenSession() throws {
    let store = makeStore();store.createProjectFolder(name:"作品")
    let folder = try XCTUnwrap(store.projectFolders.first)
    store.newProject(name:"图像",width:100,height:100,background:nil)
    let path = "/tmp/library-test.imgp"
    store.active.url = URL(fileURLWithPath:path)
    store.recentProjects = [RecentProject(path:path,name:"图像",width:100,height:100,lastOpened:Date())]
    XCTAssertTrue(store.moveStartPageLibraryItem("path:"+path,to:folder.id))
    XCTAssertEqual(store.active.libraryFolderID,folder.id);XCTAssertEqual(store.recentProjects.first?.folderID,folder.id)
    XCTAssertTrue(store.moveStartPageLibraryItem(store.active.id.uuidString,to:nil))
    XCTAssertNil(store.active.libraryFolderID);XCTAssertNil(store.recentProjects.first?.folderID)
  }
  @MainActor func testRemovingFolderKeepsChildrenAndProjectsAtParent() throws {
    let store = makeStore();store.createProjectFolder(name:"父")
    let parent = try XCTUnwrap(store.projectFolders.first)
    store.createProjectFolder(name:"子",parentID:parent.id)
    let child = try XCTUnwrap(store.projectFolders.last)
    store.createProjectFolder(name:"孙",parentID:child.id)
    let grandchild = try XCTUnwrap(store.projectFolders.last)
    store.newProject(name:"项目",width:100,height:100,background:nil)
    XCTAssertTrue(store.moveStartPageLibraryItem(store.active.id.uuidString,to:child.id))
    store.deleteProjectFolder(child.id)
    XCTAssertEqual(store.projectFolders.first(where:{$0.id == grandchild.id})?.parentID,parent.id)
    XCTAssertEqual(store.active.libraryFolderID,parent.id)
    XCTAssertFalse(store.projectFolders.contains(where:{$0.id == child.id}))
  }
}
