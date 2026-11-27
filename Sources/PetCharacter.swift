enum PetCharacter: String, CaseIterable {
    case cat, rascal, dog, rabbit, giraffe, raccoon, redPanda, otter

    var menuTitle: String {
        switch self {
        case .cat: return "Smudge（墨团）· 小黑猫"
        case .rascal: return "Rascal（小坏蛋）· 键帽大盗"
        case .dog: return "Pickles（酸黄瓜）· 小狗"
        case .rabbit: return "Pipkin（小陶罐）· 小兔"
        case .giraffe: return "Periscope（潜望镜）· 长颈鹿"
        case .raccoon: return "Bandit（小飞贼）· 小浣熊"
        case .redPanda: return "Paprika（甜椒）· 小熊猫"
        case .otter: return "Pebble（小石子）· 小水獭"
        }
    }
}
