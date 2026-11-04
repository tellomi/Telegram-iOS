import Foundation
internal import TelegramApi

func tellomiDcOptionInputs(_ dcOptions: [Api.DcOption]) -> [TellomiDcOptionInput] {
    var inputs: [TellomiDcOptionInput] = []
    for option in dcOptions {
        switch option {
        case let .dcOption(data):
            inputs.append(TellomiDcOptionInput(
                datacenterId: Int(data.id),
                host: data.ipAddress,
                port: Int(data.port),
                flags: Int(data.flags),
                secret: data.secret?.makeData()
            ))
        }
    }
    return inputs
}
