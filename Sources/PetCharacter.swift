enum PetCharacter: String, CaseIterable {
    case cat, dog, rabbit, giraffe

    var menuTitle: String {
        switch self {
        case .cat: return "Smudge（墨团）· 小黑猫"
        case .dog: return "Pickles（酸黄瓜）· 小狗"
        case .rabbit: return "Pipkin（小陶罐）· 小兔"
        case .giraffe: return "Periscope（潜望镜）· 长颈鹿"
        }
    }
}
