import AccountContext
import Display
import Foundation
import PresentationDataUtils
import TelegramCore
import TelegramPresentationData
import UIKit

extension PeerInfoScreenImpl {
    func tellomiNoteAvatarUploadFailure(_ error: UploadPeerPhotoError) {
        self.controllerNode.state = self.controllerNode.state.withUpdatingAvatar(nil).withAvatarUploadProgress(nil)
        if let (layout, navigationHeight) = self.controllerNode.validLayout {
            self.controllerNode.containerLayoutUpdated(layout: layout, navigationHeight: navigationHeight, transition: .immediate, additive: false)
        }
        let failure: TellomiSignUpAvatarFailure
        if case let .server(code, description) = error {
            failure = TellomiSignUpAvatarFailure(code: code, description: description)
        } else {
            failure = TellomiSignUpAvatarFailure(code: 500, description: "")
        }
        let strings = self.presentationData.strings
        var pack: [String: String] = [:]
        if let secondary = strings.secondaryComponent?.dict {
            for (key, value) in secondary {
                pack[key] = value
            }
        }
        for (key, value) in strings.primaryComponent.dict {
            pack[key] = value
        }
        let text = tellomiSignUpAvatarFailureText(code: failure.code, description: failure.description, languageCode: strings.primaryComponent.languageCode, pack: pack)
        self.present(textAlertController(context: self.context, updatedPresentationData: self.updatedPresentationData, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})]), in: .window(.root))
    }
}
