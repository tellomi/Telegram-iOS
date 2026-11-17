import UIKit
import XCTest
import ObjectiveC
import SwiftSignalKit
import Display
import AccountContext
import AnimationCache
import MultiAnimationRenderer
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AppBundle
@testable import ChatListUI

public final class ReorderProbeSharedAccountContext: SharedAccountContext {
}

public final class ReorderProbeAccountContext: AccountContext {
}

private final class ReorderProbeAnimationCache: AnimationCache {
    func get(sourceId: String, size: CGSize, fetch: @escaping (AnimationCacheFetchOptions) -> Disposable) -> Signal<AnimationCacheItemResult, NoError> {
        fatalError("reorder probe animation cache")
    }

    func getFirstFrameSynchronously(sourceId: String, size: CGSize) -> AnimationCacheItem? {
        fatalError("reorder probe animation cache")
    }

    func getFirstFrame(queue: Queue, sourceId: String, size: CGSize, fetch: ((AnimationCacheFetchOptions) -> Disposable)?, completion: @escaping (AnimationCacheItemResult) -> Void) -> Disposable {
        fatalError("reorder probe animation cache")
    }
}

private final class ReorderProbeAnimationRenderer: MultiAnimationRenderer {
    func add(target: MultiAnimationRenderTarget, cache: AnimationCache, itemId: String, unique: Bool, size: CGSize, fetch: @escaping (AnimationCacheFetchOptions) -> Disposable) -> Disposable {
        fatalError("reorder probe animation renderer")
    }

    func loadFirstFrameSynchronously(target: MultiAnimationRenderTarget, cache: AnimationCache, itemId: String, size: CGSize) -> Bool {
        fatalError("reorder probe animation renderer")
    }

    func loadFirstFrame(target: MultiAnimationRenderTarget, cache: AnimationCache, itemId: String, size: CGSize, fetch: ((AnimationCacheFetchOptions) -> Disposable)?, completion: @escaping (Bool, Bool) -> Void) -> Disposable {
        fatalError("reorder probe animation renderer")
    }

    func loadFirstFrameAsImage(cache: AnimationCache, itemId: String, size: CGSize, fetch: ((AnimationCacheFetchOptions) -> Disposable)?, completion: @escaping (CGImage?) -> Void) -> Disposable {
        fatalError("reorder probe animation renderer")
    }

    func setFrameIndex(itemId: String, size: CGSize, frameIndex: Int, placeholder: UIImage) {
        fatalError("reorder probe animation renderer")
    }
}

private final class FixedHeightRow: ListViewItem {
    let rowHeight: CGFloat
    let neighborDescriptor: AnyEquatable = .noNeighborInfluence

    init(rowHeight: CGFloat) {
        self.rowHeight = rowHeight
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        let node = ListViewItemNode(layerBacked: true)
        node.contentSize = CGSize(width: params.width, height: self.rowHeight)
        completion(node, { (nil, { _ in }) })
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: self.rowHeight), insets: UIEdgeInsets())
        completion(layout, { _ in })
    }
}

/// `ChatListNode.init` calls `ChatListTopReorderPreservation.install`. These cases
/// construct that initializer and then run `ListView.transaction`. They do not set
/// `preservesTopDownInsert` themselves and do not choose the insert direction.
final class ChatListTopReorderInstallationTests: XCTestCase {
    private let width: CGFloat = 390
    private let height: CGFloat = 800
    private let insetTop: CGFloat = 200
    private let row: CGFloat = 76
    private let dateFormat = PresentationDateTimeFormat(timeFormat: .military, dateFormat: .dayFirst, dateSeparator: ".", dateSuffix: "", requiresFullYear: false, decimalSeparator: ".", groupingSeparator: "")

    override class func setUp() {
        super.setUp()
        exchangeResourceLookups()
    }

    override class func tearDown() {
        exchangeResourceLookups()
        super.tearDown()
    }

    private class func exchangeResourceLookups() {
        for (original, replacement) in [
            (#selector(Bundle.path(forResource:ofType:)), #selector(Bundle.reorderProbeResourcePath(_:ofType:))),
            (#selector(Bundle.path(forResource:ofType:inDirectory:forLocalization:)), #selector(Bundle.reorderProbeLocalizedResourcePath(_:ofType:inDirectory:forLocalization:)))
        ] {
            method_exchangeImplementations(class_getInstanceMethod(Bundle.self, original)!, class_getInstanceMethod(Bundle.self, replacement)!)
        }
    }

    private func hostContentView() -> UIView {
        let delegateWindow = UIApplication.shared.delegate?.window ?? nil
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let sceneWindow = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.flatMap { $0.windows }.first
        let window = delegateWindow ?? sceneWindow
        XCTAssertNotNil(window, "host delegate window and scene windows are both nil")
        XCTAssertTrue(window?.isKeyWindow == true)
        let view = window?.rootViewController?.view
        XCTAssertNotNil(view)
        return view!
    }

    private func makeInstalledNode(enabled: Bool) -> ChatListNode {
        let frame = CGRect(x: 0, y: 0, width: self.width, height: self.height)
        let content = self.hostContentView()
        fputs("reorder-diag: host window ready\n", stderr)
        fflush(stderr)
        ChatListTopReorderPreservation.enabled = enabled
        ChatListTopReorderPreservation.returnAfterInstall = true
        fputs("reorder-diag: creating ChatListNode\n", stderr)
        fflush(stderr)
        let node = ChatListNode(
            context: ReorderProbeAccountContext(),
            location: .chatList(groupId: .root),
            previewing: false,
            fillPreloadItems: false,
            mode: .chatList(appendContacts: false),
            theme: defaultPresentationTheme,
            fontSize: .regular,
            strings: defaultPresentationStrings,
            dateTimeFormat: self.dateFormat,
            nameSortOrder: .firstLast,
            nameDisplayOrder: .firstLast,
            animationCache: ReorderProbeAnimationCache(),
            animationRenderer: ReorderProbeAnimationRenderer(),
            disableAnimations: true,
            isInlineMode: false,
            autoSetReady: false,
            isMainTab: nil
        )
        fputs("reorder-diag: ChatListNode created\n", stderr)
        fflush(stderr)
        node.useMainQueueTransactions = true
        node.frame = frame
        content.addSubview(node.view)
        node.view.frame = frame
        return node
    }

    private func perform(_ list: ChatListNode, delete: [ListViewDeleteItem] = [], insert: [ListViewInsertItem] = [], size: ListViewUpdateSizeAndInsets? = nil) {
        let done = expectation(description: "transaction")
        list.transaction(
            deleteIndices: delete,
            insertIndicesAndItems: insert,
            updateIndicesAndItems: [],
            options: [.Synchronous],
            updateSizeAndInsets: size,
            updateOpaqueState: nil,
            completion: { _ in
                done.fulfill()
            }
        )
        wait(for: [done], timeout: 5)
        let drained = expectation(description: "transaction queue")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 5)
    }

    private func populate(_ list: ChatListNode) {
        let rows = (0 ..< 8).map { _ in FixedHeightRow(rowHeight: self.row) }
        let inserts = rows.enumerated().map { index, row in
            ListViewInsertItem(index: index, previousIndex: nil, item: row, directionHint: nil)
        }
        self.perform(list, insert: inserts, size: ListViewUpdateSizeAndInsets(
            size: CGSize(width: self.width, height: self.height),
            insets: UIEdgeInsets(top: self.insetTop, left: 0, bottom: 0, right: 0),
            duration: 0,
            curve: .Default(duration: nil)
        ))
    }

    private func topMinY(_ list: ChatListNode) -> CGFloat {
        guard let node = list.itemNodeAtIndex(0) else {
            XCTFail("row 0 is missing")
            return 0
        }
        return node.frame.minY
    }

    private func scroll(_ list: ChatListNode, by delta: CGFloat) -> CGFloat {
        let before = self.topMinY(list)
        let offset = list.scroller.contentOffset
        list.scroller.setContentOffset(CGPoint(x: offset.x, y: offset.y + delta), animated: false)
        let after = self.topMinY(list)
        XCTAssertEqual(after, before - delta, accuracy: 0.5)
        return after
    }

    private func promote(_ list: ChatListNode, from index: Int) {
        self.perform(
            list,
            delete: [ListViewDeleteItem(index: index, directionHint: nil)],
            insert: [ListViewInsertItem(index: 0, previousIndex: index, item: FixedHeightRow(rowHeight: self.row), directionHint: .Down)]
        )
    }

    override func tearDown() {
        ChatListTopReorderPreservation.returnAfterInstall = false
        ChatListTopReorderPreservation.enabled = true
        super.tearDown()
    }

    func testInstalledNodeKeepsTheCollapsedAnchor() {
        let node = self.makeInstalledNode(enabled: true)
        XCTAssertTrue(node.preservesTopDownInsert)
        self.populate(node)
        let anchor = self.scroll(node, by: 54)
        self.promote(node, from: 1)
        XCTAssertEqual(self.topMinY(node), anchor, accuracy: 0.5)
        self.promote(node, from: 4)
        XCTAssertEqual(self.topMinY(node), anchor, accuracy: 0.5)
    }

    func testNodeInstalledWhileDisabledFollowsTheUpstreamJump() {
        let node = self.makeInstalledNode(enabled: false)
        XCTAssertFalse(node.preservesTopDownInsert)
        self.populate(node)
        let anchor = self.scroll(node, by: 54)
        self.promote(node, from: 1)
        XCTAssertEqual(self.topMinY(node), anchor - self.row, accuracy: 0.5)
    }
}

private extension Bundle {
    @objc func reorderProbeResourcePath(_ name: String?, ofType type: String?) -> String? {
        if name == "PresentationStrings", type == "data", self == getAppBundle() {
            return Bundle(for: ChatListTopReorderInstallationTests.self).reorderProbeResourcePath(name, ofType: type)
        }
        return self.reorderProbeResourcePath(name, ofType: type)
    }

    @objc func reorderProbeLocalizedResourcePath(_ name: String?, ofType type: String?, inDirectory directory: String?, forLocalization localization: String?) -> String? {
        if name == "Localizable", type == "strings", self == getAppBundle() {
            return Bundle(for: ChatListTopReorderInstallationTests.self).reorderProbeLocalizedResourcePath(name, ofType: type, inDirectory: directory, forLocalization: localization)
        }
        return self.reorderProbeLocalizedResourcePath(name, ofType: type, inDirectory: directory, forLocalization: localization)
    }
}
