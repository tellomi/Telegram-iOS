import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

func tellomiLanguageBarItem(target: Any?, action: Selector) -> UIBarButtonItem {
    let image = tellomiSymbol("globe", pointSize: 20.0)?.withRenderingMode(.alwaysTemplate)
    let item = UIBarButtonItem(image: image, style: .plain, target: target, action: action)
    item.accessibilityLabel = "Language"
    item.accessibilityIdentifier = "Auth.Login.Language"
    return item
}

/// Pushed with the same modal navigation presentation as
/// `AuthorizationSequenceCountrySelectionController` (`glass: true`).
/// Rows match Telegram's language list: English name, native name, checkmark.
final class TellomiLanguageSelectionController: ViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let theme: PresentationTheme
    private let account: UnauthorizedAccount?
    private var languages: [LocalizationInfo]
    private var filtered: [LocalizationInfo]
    private var query = ""
    private let selectedCode: String
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchBar = UISearchBar(frame: .zero)
    private let listDisposable = MetaDisposable()

    var completeWithLanguage: ((LocalizationInfo) -> Void)?

    init(presentationData: PresentationData, account: UnauthorizedAccount?, selectedCode: String) {
        self.theme = presentationData.theme
        self.account = account
        self.selectedCode = selectedCode.lowercased()
        let initial = tellomiBuiltinInterfaceLanguages()
        self.languages = initial
        self.filtered = initial

        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: presentationData.theme), strings: NavigationBarStrings(presentationStrings: presentationData.strings)))

        self._hasGlassStyle = true
        self.navigationPresentation = .modal
        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style

        let copy = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(presentationData.strings))
        self.title = copy.chooseLanguage

        self.searchBar.placeholder = presentationData.strings.Common_Search
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.delegate = self
        self.searchBar.autocapitalizationType = .none
        self.searchBar.autocorrectionType = .no

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = .onDrag
        self.tableView.tableHeaderView = self.searchBar
        if #available(iOS 15.0, *) {
            self.tableView.sectionHeaderTopPadding = 0.0
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.listDisposable.dispose()
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.setViewBlock({
            return UITracingLayerView()
        })
        self.displayNode = node
        self.applyColors()
        node.view.addSubview(self.tableView)
        self.displayNodeDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.loadServerLanguages()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        let frame = CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top))
        transition.updateFrame(view: self.tableView, frame: frame)
        let width = layout.size.width
        self.searchBar.frame = CGRect(x: 0.0, y: 0.0, width: width, height: 52.0)
        self.tableView.tableHeaderView = self.searchBar
        var insets = layout.safeInsets
        insets.top = 0.0
        if let inputHeight = layout.inputHeight, inputHeight > 0.0 {
            insets.bottom = inputHeight
        }
        self.tableView.contentInset = insets
        self.tableView.scrollIndicatorInsets = insets
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let info = self.filtered[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "lang") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "lang")
        let palette = TellomiLoginChrome.palette(dark: self.theme.overallDarkAppearance)
        cell.backgroundColor = palette.rowBackground
        cell.textLabel?.textColor = palette.rowText
        cell.detailTextLabel?.textColor = palette.secondaryText
        cell.textLabel?.font = Font.regular(17.0)
        cell.detailTextLabel?.font = Font.regular(14.0)
        cell.textLabel?.text = info.localizedTitle
        if info.title.caseInsensitiveCompare(info.localizedTitle) == .orderedSame {
            cell.detailTextLabel?.text = nil
        } else {
            cell.detailTextLabel?.text = info.title
        }
        let checked = info.languageCode.lowercased() == self.selectedCode
        cell.accessoryType = checked ? .checkmark : .none
        cell.tintColor = palette.rowText
        cell.selectionStyle = .default
        cell.accessibilityTraits = checked ? [.button, .selected] : [.button]
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let info = self.filtered[indexPath.row]
        self.completeWithLanguage?(info)
        self.dismiss()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.query = searchText
        self.applyFilter()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    private func applyColors() {
        let background = self.theme.list.blocksBackgroundColor
        self.displayNode.backgroundColor = background
        self.tableView.backgroundColor = background
        self.searchBar.barTintColor = background
        self.searchBar.tintColor = TellomiLoginChrome.palette(dark: self.theme.overallDarkAppearance).rowText
        let field = self.searchBar.searchTextField
        field.textColor = TellomiLoginChrome.palette(dark: self.theme.overallDarkAppearance).fieldText
        field.keyboardAppearance = self.theme.rootController.keyboardColor.keyboardAppearance
    }

    private func applyFilter() {
        let query = self.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            self.filtered = self.languages
        } else {
            self.filtered = self.languages.filter { info in
                info.localizedTitle.lowercased().contains(query) || info.title.lowercased().contains(query) || info.languageCode.lowercased().contains(query)
            }
        }
        self.tableView.reloadData()
    }

    private func loadServerLanguages() {
        guard let account = self.account else {
            return
        }
        self.listDisposable.set((TelegramEngineUnauthorized(account: account).localization.availableLocalizations()
        |> deliverOnMainQueue).start(next: { [weak self] remote in
            guard let self, !remote.isEmpty else {
                return
            }
            self.languages = tellomiMergedInterfaceLanguages(server: remote)
            self.applyFilter()
        }))
    }
}
