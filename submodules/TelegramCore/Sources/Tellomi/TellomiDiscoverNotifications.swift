import Foundation
import SwiftSignalKit
import TellomiDiscover
internal import TelegramApi

/// Writes the discover activity switch onto user 777005 (`@faxian`).
/// teamgram `push.DeliverActivity` drops the push when that peer is muted.
/// `mute_until` 0 is on. `Int32.max` is off. A missing row is on.
public func tellomiFetchDiscoverNotificationEnabled(account: Account) -> Signal<Bool?, NoError> {
    let peer = Api.InputPeer.inputPeerUser(.init(userId: tellomiDiscoverNotifyUserId, accessHash: 0))
    return account.network.request(Api.functions.account.getNotifySettings(peer: .inputNotifyPeer(.init(peer: peer))))
    |> map { settings -> Bool? in
        guard case let .peerNotifySettings(data) = settings else {
            return nil
        }
        return tellomiDiscoverNotificationsEnabled(muteUntil: data.muteUntil, now: Int64(Date().timeIntervalSince1970))
    }
    |> `catch` { _ -> Signal<Bool?, NoError> in
        return .single(nil)
    }
}

public func tellomiPushDiscoverNotificationEnabled(account: Account, enabled: Bool) -> Signal<Void, NoError> {
    let peer = Api.InputPeer.inputPeerUser(.init(userId: tellomiDiscoverNotifyUserId, accessHash: 0))
    let muteUntil: Int32 = enabled ? 0 : Int32.max
    let flags: Int32 = 1 << 2
    let settings = Api.InputPeerNotifySettings.inputPeerNotifySettings(.init(flags: flags, showPreviews: nil, silent: nil, muteUntil: muteUntil, sound: nil, storiesMuted: nil, storiesHideSender: nil, storiesSound: nil))
    return account.network.request(Api.functions.account.updateNotifySettings(peer: .inputNotifyPeer(.init(peer: peer)), settings: settings))
    |> map { _ -> Void in
        return ()
    }
    |> `catch` { _ -> Signal<Void, NoError> in
        return .single(())
    }
}
