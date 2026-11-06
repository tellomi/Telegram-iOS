import Display
import PhotosUI
import UIKit

@available(iOS 14.0, *)
final class TellomiDiscoverPhotoPicker: NSObject, PHPickerViewControllerDelegate {
    var onData: (([Data]) -> Void)?

    func present(from host: UIViewController, limit: Int) {
        guard limit > 0 else {
            return
        }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = limit
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        host.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        self.load(results.map(\.itemProvider), into: []) { [weak self] datas in
            self?.onData?(datas)
        }
    }

    private func load(_ providers: [NSItemProvider], into datas: [Data], completion: @escaping ([Data]) -> Void) {
        guard let provider = providers.first else {
            completion(datas)
            return
        }
        let rest = Array(providers.dropFirst())
        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
            var next = datas
            if let data {
                next.append(data)
            }
            DispatchQueue.main.async {
                self.load(rest, into: next, completion: completion)
            }
        }
    }
}

final class TellomiDiscoverImageRow: UIView {
    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    private let picture = UIImageView()
    private let label = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.picture.contentMode = .scaleAspectFill
        self.picture.clipsToBounds = true
        self.picture.layer.cornerRadius = 6.0
        self.label.font = Font.regular(13.0)
        self.label.numberOfLines = 2
        self.cancelButton.addTarget(self, action: #selector(self.cancelPressed), for: .touchUpInside)
        self.retryButton.addTarget(self, action: #selector(self.retryPressed), for: .touchUpInside)
        self.addSubview(self.picture)
        self.addSubview(self.label)
        self.addSubview(self.cancelButton)
        self.addSubview(self.retryButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(image: UIImage?, text: String, failed: Bool, cancelTitle: String, retryTitle: String, color: UIColor, destructive: UIColor) {
        self.picture.image = image
        self.picture.backgroundColor = color.withAlphaComponent(0.12)
        self.label.text = text
        self.label.textColor = failed ? destructive : color
        self.cancelButton.setTitle(cancelTitle, for: .normal)
        self.retryButton.setTitle(retryTitle, for: .normal)
        self.retryButton.isHidden = !failed
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.picture.frame = CGRect(x: 0.0, y: 4.0, width: 56.0, height: 56.0)
        let retryWidth: CGFloat = self.retryButton.isHidden ? 0.0 : 64.0
        self.retryButton.frame = CGRect(x: self.bounds.width - retryWidth, y: 16.0, width: retryWidth, height: 32.0)
        let cancelX = self.bounds.width - retryWidth - 64.0
        self.cancelButton.frame = CGRect(x: cancelX, y: 16.0, width: 64.0, height: 32.0)
        self.label.frame = CGRect(x: 64.0, y: 4.0, width: max(1.0, cancelX - 72.0), height: 56.0)
    }

    @objc private func cancelPressed() {
        self.onCancel?()
    }

    @objc private func retryPressed() {
        self.onRetry?()
    }
}
